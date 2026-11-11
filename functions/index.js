const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { defineSecret } = require("firebase-functions/params");

const stripeSecret = defineSecret("STRIPE_SECRET_KEY");
const webhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

admin.initializeApp();

function formatDateEs(dateStr) {
  if (!dateStr) return "";
  if (dateStr.includes('/')) return dateStr;
  const parts = dateStr.split('-');
  if (parts.length === 3) {
    return `${parts[2]}/${parts[1]}/${parts[0]}`;
  }
  return dateStr;
}

async function addCompletedHours(clientId, caregiverId, bookingSlot) {
  let hours = 1;
  try {
    if (bookingSlot && bookingSlot.includes('-')) {
      const parts = bookingSlot.split('-');
      const start = parts[0].split(':')[0];
      const end = parts[1].split(':')[0];
      hours = Math.abs(parseInt(end) - parseInt(start));
      if (hours === 0) hours = 1;
    }
  } catch(e) {
    console.error("Error calculating hours:", e);
  }
  
  const docId = `${clientId}_${caregiverId}`;
  await admin.firestore().collection('client_caregiver_stats').doc(docId).set({
    clientId: clientId,
    caregiverId: caregiverId,
    accumulatedHours: admin.firestore.FieldValue.increment(hours),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });
}
exports.createConnectAccount = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  try {
    const caregiverRef = admin.firestore().collection("caregivers").doc(context.auth.uid);
    const caregiverSnap = await caregiverRef.get();
    if (caregiverSnap.exists && caregiverSnap.data().stripeAccountId) {
      return { accountId: caregiverSnap.data().stripeAccountId, existing: true };
    }
    const email = context.auth.token.email || "cuidador@senicare.app";
    const account = await stripe.accounts.create({
      type: "express", country: "ES", email: email,
      capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
      business_type: "individual",
    });
    await caregiverRef.set({ stripeAccountId: account.id }, { merge: true });
    return { accountId: account.id };
  } catch (error) { throw new functions.https.HttpsError("internal", error.message); }
});

exports.getStripeAccountLink = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  try {
    if (data.mode === "dashboard" || data.type === "login_link") {
      try {
        const loginLink = await stripe.accounts.createLoginLink(data.accountId);
        return { url: loginLink.url, type: "login_link" };
      } catch (loginError) {
        console.log("Cuenta Express aún en onboarding, generando account_onboarding link:", loginError.message);
      }
    }
    const accountLink = await stripe.accountLinks.create({
      account: data.accountId,
      refresh_url: "https://senicare-3342d.web.app/reauth",
      return_url: "https://senicare-3342d.web.app/return",
      type: "account_onboarding",
    });
    return { url: accountLink.url, type: "account_onboarding" };
  } catch (error) { throw new functions.https.HttpsError("internal", error.message); }
});

exports.syncStripeKycStatus = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  try {
    const uid = context.auth.uid;
    const caregiverDoc = await admin.firestore().collection("caregivers").doc(uid).get();
    if (!caregiverDoc.exists || !caregiverDoc.data().stripeAccountId) {
      return { isVerified: false, reason: "No Stripe account" };
    }
    
    const accountId = caregiverDoc.data().stripeAccountId;
    const account = await stripe.accounts.retrieve(accountId);
    
    const isVerified = account.details_submitted && account.charges_enabled;
    
    await admin.firestore().collection("caregivers").doc(uid).update({
      isKycVerified: isVerified
    });
    
    return { isVerified: isVerified };
  } catch (error) { throw new functions.https.HttpsError("internal", error.message); }
});


exports.createSecureBooking = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
    const stripe = require("stripe")(stripeSecret.value());
    const db = admin.firestore();
    
    try {
        const { caregiverId, offerId, applicationId, sessions, clientLatitude, clientLongitude } = data;
        
        let pricePerHour = 0;
        let caregiverName = "";
        let stripeAccountId = "";
        let clientFeeRate = 0.10;
        let urgencyBonusRate = 0.0;
        
        const caregiverDoc = await db.collection("caregivers").doc(caregiverId).get();
        if (!caregiverDoc.exists) throw new functions.https.HttpsError("not-found", "Caregiver not found");
        caregiverName = caregiverDoc.data().name;
        stripeAccountId = caregiverDoc.data().stripeAccountId;
        
        if (!stripeAccountId) {
            throw new functions.https.HttpsError("failed-precondition", "Caregiver has no stripe account");
        }

        if (offerId && applicationId) {
            const appDoc = await db.collection("jobOffers").doc(offerId).collection("applications").doc(applicationId).get();
            if (!appDoc.exists) throw new functions.https.HttpsError("not-found", "Application not found");
            pricePerHour = appDoc.data().proposedPrice;
            
            const offerDoc = await db.collection("jobOffers").doc(offerId).get();
            if (offerDoc.exists) {
                clientFeeRate = offerDoc.data().clientFeeRate || 0.10;
                urgencyBonusRate = offerDoc.data().urgencyBonusRate || 0.0;
            }
        } else {
            pricePerHour = caregiverDoc.data().pricePerHour;
        }

        let totalPaidOverall = 0;
        const transferGroup = `booking_${Date.now()}`;
        const bookingsToCreate = [];

        for (const session of sessions) {
            const { day, slot, totalHours } = session;
            const cost = pricePerHour * totalHours;
            const clientFee = cost * clientFeeRate;
            const commissionRate = 0.18 - urgencyBonusRate;
            const commissionAmount = cost * commissionRate;
            const caregiverPayout = cost - commissionAmount;
            const totalPaid = cost + clientFee;
            
            totalPaidOverall += totalPaid;
            
            const bookingRef = db.collection("bookings").doc();
            bookingsToCreate.push({
                ref: bookingRef,
                data: {
                    id: bookingRef.id,
                    clientId: context.auth.uid,
                    caregiverId: caregiverId,
                    caregiverName: caregiverName,
                    day: day,
                    slot: slot,
                    clientLatitude: clientLatitude || null,
                    clientLongitude: clientLongitude || null,
                    cost: cost,
                    clientFee: clientFee,
                    caregiverCommissionRate: commissionRate,
                    caregiverCommissionAmount: commissionAmount,
                    caregiverPayout: caregiverPayout,
                    totalPaid: totalPaid,
                    status: "pendingPayment",
                    transferGroup: transferGroup,
                    escrowStatus: "none",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    isReviewed: false
                }
            });
        }
        
        const amountInCents = Math.round(totalPaidOverall * 100);
        
        const paymentIntent = await stripe.paymentIntents.create({
            amount: amountInCents,
            currency: "eur",
            payment_method_types: ["card"],
            transfer_group: transferGroup
        });
        
        const batch = db.batch();
        for (const b of bookingsToCreate) {
            b.data.paymentIntentId = paymentIntent.id;
            batch.set(b.ref, b.data);
        }
        await batch.commit();
        
        return { 
            clientSecret: paymentIntent.client_secret, 
            paymentIntentId: paymentIntent.id
        };
    } catch (error) {
        console.error("Secure Booking Error: ", error);
        throw new functions.https.HttpsError("internal", error.message);
    }
});

exports.createPaymentIntent = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  try {
    const paymentIntent = await stripe.paymentIntents.create({
      amount: data.amountInCents, currency: "eur", payment_method_types: ["card"], transfer_group: `booking_${Date.now()}`
    });
    return { clientSecret: paymentIntent.client_secret, transferGroup: paymentIntent.transfer_group, paymentIntentId: paymentIntent.id };
  } catch (error) { 
    console.error("Stripe Error Details: ", error);
    throw new functions.https.HttpsError("internal", error.message); 
  }
});

async function reopenBookingSlots(caregiverId, day, slotRange) {
  if (!caregiverId || !day || !slotRange) return;
  try {
    const slotsRef = admin.firestore().collection("caregivers").doc(caregiverId)
      .collection("availability").doc(day).collection("slots");
    if (slotRange.includes("-")) {
      const parts = slotRange.split("-");
      const startHour = parseInt(parts[0].split(":")[0], 10);
      const endHour = parseInt(parts[1].split(":")[0], 10);
      if (!isNaN(startHour) && !isNaN(endHour) && endHour > startHour) {
        const batch = admin.firestore().batch();
        for (let h = startHour; h < endHour; h++) {
          const slotId = `${String(h).padStart(2, "0")}:00`;
          batch.set(slotsRef.doc(slotId), { isAvailable: true }, { merge: true });
        }
        await batch.commit();
        return;
      }
    }
    await slotsRef.doc(slotRange).set({ isAvailable: true }, { merge: true });
  } catch (e) {
    console.warn("Error reopening slots:", e.message);
  }
}

async function createLinkedStripeTransfer(stripe, { amountInCents, destination, paymentIntentId, transferGroup, idempotencyKey }) {
  let sourceTransaction = null;
  if (paymentIntentId) {
    try {
      const pi = await stripe.paymentIntents.retrieve(paymentIntentId);
      if (pi && pi.latest_charge) sourceTransaction = pi.latest_charge;
    } catch (e) {
      console.warn("Could not retrieve latest_charge for transfer, using transfer_group fallback:", e.message);
    }
  }
  const params = {
    amount: Math.round(amountInCents),
    currency: "eur",
    destination: destination,
  };
  if (sourceTransaction) {
    params.source_transaction = sourceTransaction;
  } else if (transferGroup) {
    params.transfer_group = transferGroup;
  }
  const options = idempotencyKey ? { idempotencyKey } : undefined;
  return await stripe.transfers.create(params, options);
}

async function createIdempotentRefund(stripe, { paymentIntentId, amountInCents, idempotencyKey }) {
  const params = {
    payment_intent: paymentIntentId,
    amount: Math.round(amountInCents),
  };
  const options = idempotencyKey ? { idempotencyKey } : undefined;
  return await stripe.refunds.create(params, options);
}

exports.releaseEscrowPayment = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  try {
    const bookingId = data.bookingId;
    if (!bookingId) throw new functions.https.HttpsError("invalid-argument", "bookingId is required.");

    const bookingDoc = await admin.firestore().collection("bookings").doc(bookingId).get();
    if (!bookingDoc.exists) throw new functions.https.HttpsError("not-found", "Booking not found.");
    
    const booking = bookingDoc.data();
    
    // Security check: only the client who made the booking or an admin can release the escrow
    if (booking.clientId !== context.auth.uid) {
      if (context.auth.token.email !== "maverick6576@gmail.com") {
        throw new functions.https.HttpsError("permission-denied", "No autorizado para liberar este pago.");
      }
    }

    if (booking.escrowStatus !== "held" && booking.escrowStatus !== "pending") {
      throw new functions.https.HttpsError("failed-precondition", "El pago ya ha sido liberado o reembolsado.");
    }

    if (!booking.checkInTime && context.auth.token.email !== "maverick6576@gmail.com") {
      throw new functions.https.HttpsError("failed-precondition", "No se puede liberar el pago: el cuidador no ha realizado el Check-in (no se ha presentado en el domicilio).");
    }

    const caregiverDoc = await admin.firestore().collection("caregivers").doc(booking.caregiverId).get();
    if (!caregiverDoc.exists || !caregiverDoc.data().stripeAccountId) {
      throw new functions.https.HttpsError("failed-precondition", "El cuidador no tiene cuenta de Stripe configurada.");
    }

    const destinationAccountId = caregiverDoc.data().stripeAccountId;
    const amountInCents = Math.round(booking.caregiverPayout * 100);

    const transfer = await createLinkedStripeTransfer(stripe, {
      amountInCents,
      destination: destinationAccountId,
      paymentIntentId: booking.paymentIntentId,
      transferGroup: booking.transferGroup,
      idempotencyKey: `release_${bookingId}`,
    });

    await admin.firestore().collection("bookings").doc(bookingId).update({
      escrowStatus: "released_manual",
      status: "completed"
    });
    await addCompletedHours(booking.clientId, booking.caregiverId, booking.slot);

    return { transferId: transfer.id, success: true };
  } catch (error) { 
    console.error("Error in releaseEscrowPayment:", error);
    throw new functions.https.HttpsError("internal", error.message); 
  }
});

exports.cancelBookingProcess = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  const { bookingId, reason, isLate } = data;
  try {
    const bookingDoc = await admin.firestore().collection("bookings").doc(bookingId).get();
    if (!bookingDoc.exists) throw new functions.https.HttpsError("not-found", "Booking not found.");
    
    const booking = bookingDoc.data();
    
    // Security check: only involved users can cancel
    if (booking.clientId !== context.auth.uid && booking.caregiverId !== context.auth.uid) {
      if (context.auth.token.email !== "maverick6576@gmail.com") {
        throw new functions.https.HttpsError("permission-denied", "No autorizado para cancelar esta reserva.");
      }
    }

    if (booking.status === "cancelled" || booking.status === "cancelledLate" || booking.escrowStatus === "refunded") {
      return { success: true, alreadyCancelled: true };
    }

    if (!isLate) {
      // Devolver todo menos un 5% de gastos de gestión (con un mínimo de 1.00€ para cubrir comisiones de pasarela)
      const managementFee = Math.max(1.00, booking.cost * 0.05);
      let refundAmount = booking.totalPaid - managementFee;
      if (refundAmount < 0) refundAmount = 0;
      
      if (booking.paymentIntentId && refundAmount > 0) {
        await createIdempotentRefund(stripe, {
          paymentIntentId: booking.paymentIntentId,
          amountInCents: Math.round(refundAmount * 100),
          idempotencyKey: `cancel_refund_${bookingId}`,
        });
      }
      await admin.firestore().collection("bookings").doc(bookingId).update({ status: "cancelled", escrowStatus: "refunded", cancellationReason: reason });
      await reopenBookingSlots(booking.caregiverId, booking.day, booking.slot);
      return { success: true };
    }
    // Cancelación Tardía (10% de castigo a la mitad de cada uno = 45% limpio)
    const refundAmount = booking.cost * 0.45;
    if (booking.paymentIntentId && refundAmount > 0) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: Math.round(refundAmount * 100),
        idempotencyKey: `late_cancel_refund_${bookingId}`,
      });
    }
    const caregiverDoc = await admin.firestore().collection("caregivers").doc(booking.caregiverId).get();
    if (caregiverDoc.data()?.stripeAccountId && (booking.paymentIntentId || booking.transferGroup)) {
      const caregiverPayout = booking.cost * 0.45;
      if (caregiverPayout > 0) {
        await createLinkedStripeTransfer(stripe, {
          amountInCents: Math.round(caregiverPayout * 100),
          destination: caregiverDoc.data().stripeAccountId,
          paymentIntentId: booking.paymentIntentId,
          transferGroup: booking.transferGroup,
          idempotencyKey: `late_cancel_transfer_${bookingId}`,
        });
      }
    }
    await admin.firestore().collection("bookings").doc(bookingId).update({ status: "cancelledLate", escrowStatus: "resolved_partial", cancellationReason: reason });
    await reopenBookingSlots(booking.caregiverId, booking.day, booking.slot);
    return { success: true };
  } catch (error) { throw new functions.https.HttpsError("internal", error.message); }
});

  // Función para que el cuidador rechace una reserva y se emita el reembolso completo al cliente
  exports.caregiverRejectBooking = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
    const stripe = require("stripe")(stripeSecret.value());
    const { bookingId } = data;
    try {
      const bookingDoc = await admin.firestore().collection("bookings").doc(bookingId).get();
      if (!bookingDoc.exists) throw new functions.https.HttpsError("not-found", "Booking not found.");
      
      const booking = bookingDoc.data();
      
      // Validar que es el cuidador
      if (booking.caregiverId !== context.auth.uid) {
        throw new functions.https.HttpsError("permission-denied", "Solo el cuidador asignado puede rechazar esta reserva.");
      }

      if (booking.status === "cancelled" || booking.status === "cancelledLate" || booking.status === "completed") {
         throw new functions.https.HttpsError("failed-precondition", "La reserva ya está finalizada o cancelada.");
      }

      // Reembolso total (fue culpa/elección del cuidador)
      const refundAmount = booking.totalPaid || 0;
      if (booking.paymentIntentId && refundAmount > 0) {
        await createIdempotentRefund(stripe, {
          paymentIntentId: booking.paymentIntentId,
          amountInCents: Math.round(refundAmount * 100),
          idempotencyKey: `reject_refund_${bookingId}`,
        });
      }

      await admin.firestore().collection("bookings").doc(bookingId).update({ 
        status: "cancelled", 
        escrowStatus: "refunded", 
        cancellationReason: "Rechazada por el cuidador" 
      });
      await reopenBookingSlots(booking.caregiverId, booking.day, booking.slot);

      return { success: true };
    } catch (error) { throw new functions.https.HttpsError("internal", error.message); }
  });

exports.autoReleaseEscrowCron = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).pubsub.schedule('every 1 hours').onRun(async (context) => {
  const stripe = require("stripe")(stripeSecret.value());
  const now = new Date();

  // 0. Limpieza automática de bloqueos temporales (Hold System TTL: > 30 min en pendingPayment)
  try {
    const staleHolds = await admin.firestore().collection("bookings").where("status", "==", "pendingPayment").get();
    for (const holdDoc of staleHolds.docs) {
      const hb = holdDoc.data();
      const createdAt = hb.createdAt ? hb.createdAt.toDate() : null;
      const ageMs = createdAt ? (now.getTime() - createdAt.getTime()) : (35 * 60 * 1000);
      if (ageMs > 30 * 60 * 1000) {
        await reopenBookingSlots(hb.caregiverId, hb.day, hb.slot);
        await holdDoc.ref.delete();
      }
    }
  } catch (holdErr) {
    console.warn("Error cleaning stale pendingPayment holds:", holdErr.message);
  }
  
  // 0.5. Expiración automática de reservas en estado "pending" (no aceptadas por el cuidador a tiempo)
  try {
    const pendingSnap = await admin.firestore().collection("bookings")
      .where("escrowStatus", "==", "held")
      .where("status", "==", "pending")
      .get();
    for (const pDoc of pendingSnap.docs) {
      const pb = pDoc.data();
      let pDateParts;
      if (pb.day && pb.day.includes("/")) {
        const parts = pb.day.split("/");
        pDateParts = [parts[2], parts[1], parts[0]];
      } else if (pb.day) {
        pDateParts = pb.day.split("-");
      }
      if (pDateParts && pDateParts.length === 3 && pb.slot) {
        const startStr = pb.slot.includes("-") ? pb.slot.split("-")[0] : pb.slot;
        const startParts = startStr.split(":");
        const scheduledStart = new Date(
          parseInt(pDateParts[0], 10),
          parseInt(pDateParts[1], 10) - 1,
          parseInt(pDateParts[2], 10),
          parseInt(startParts[0], 10),
          parseInt(startParts[1] || "0", 10)
        );
        if (now > scheduledStart) {
          const fullRefund = pb.totalPaid || pb.cost || 0;
          if (pb.paymentIntentId && fullRefund > 0) {
            await createIdempotentRefund(stripe, {
              paymentIntentId: pb.paymentIntentId,
              amountInCents: Math.round(fullRefund * 100),
              idempotencyKey: `expired_pending_refund_${pDoc.id}`,
            });
          }
          await reopenBookingSlots(pb.caregiverId, pb.day, pb.slot);
          await pDoc.ref.update({
            status: "cancelled",
            escrowStatus: "refunded",
            cancellationReason: "Expirada sin respuesta del cuidador",
          });
        }
      }
    }
  } catch (pendingErr) {
    console.warn("Error expiring unaccepted pending bookings:", pendingErr.message);
  }

  // 1. Manejo de reservas normales y No-Shows (24h tras fin teórico)
  const snapshot = await admin.firestore().collection("bookings").where("escrowStatus", "==", "held").where("status", "==", "confirmed").get();
  
  for (const doc of snapshot.docs) {
    const b = doc.data();
    
    // Parsear el día y el horario (Ej: 2026-07-15 y 10:00-14:00)
    let dateParts;
    if (b.day.includes('/')) {
      const parts = b.day.split('/');
      dateParts = [parts[2], parts[1], parts[0]]; // [yyyy, mm, dd]
    } else {
      dateParts = b.day.split('-'); // [yyyy, mm, dd]
    }
    const slotParts = b.slot.split('-');
    
    if (dateParts.length === 3 && slotParts.length === 2) {
      const endParts = slotParts[1].split(':');
      const theoreticalEndTime = new Date(parseInt(dateParts[0]), parseInt(dateParts[1]) - 1, parseInt(dateParts[2]), parseInt(endParts[0]), parseInt(endParts[1]));
      
      const payoutTime = new Date(theoreticalEndTime.getTime() + (24 * 60 * 60 * 1000));
      
      if (now > payoutTime) {
        try {
          if (!b.checkInTime) {
            // NO-SHOW: Cancelación fulminante (reembolso íntegro al cliente)
            const fullRefund = b.totalPaid || b.cost || 0;
            if (b.paymentIntentId && fullRefund > 0) {
              await createIdempotentRefund(stripe, {
                paymentIntentId: b.paymentIntentId,
                amountInCents: Math.round(fullRefund * 100),
                idempotencyKey: `noshow_refund_${doc.id}`,
              });
            }
            await doc.ref.update({ status: "cancelledLate", escrowStatus: "refunded", cancellationReason: "No-Show" });
            
            // Castigo al cuidador (No-Show es una incidencia)
            await addIncidentToCaregiver(b.caregiverId);
          } else {
            // CHECKED IN: Evaluar si llegó tarde
            const startParts = slotParts[0].split(':');
            const theoreticalStartTime = new Date(parseInt(dateParts[0]), parseInt(dateParts[1]) - 1, parseInt(dateParts[2]), parseInt(startParts[0]), parseInt(startParts[1]));
            const checkInDate = b.checkInTime.toDate();
            
            const totalTheoreticalMinutes = (theoreticalEndTime.getTime() - theoreticalStartTime.getTime()) / 60000;
            const pricePerMinute = b.cost / totalTheoreticalMinutes;
            
            const minutesLate = (checkInDate.getTime() - theoreticalStartTime.getTime()) / 60000;
            
            if (minutesLate > 15) {
              // LLEGADA TARDE > 15 mins
              const amountToDeduct = minutesLate * pricePerMinute;
              const newCost = Math.max(0, b.cost - amountToDeduct);
              
              // Recalcular comision y payout
              const newCommission = newCost * b.caregiverCommissionRate;
              const newPayout = newCost - newCommission;
              const amountToRefund = b.cost - newCost; // Devolver al cliente el costo del tiempo perdido
              
              if (b.paymentIntentId && amountToRefund > 0) {
                await createIdempotentRefund(stripe, {
                  paymentIntentId: b.paymentIntentId,
                  amountInCents: Math.round(amountToRefund * 100),
                  idempotencyKey: `late_checkin_refund_${doc.id}`,
                });
              }
              
              const caregiverDoc = await admin.firestore().collection("caregivers").doc(b.caregiverId).get();
              if (caregiverDoc.data()?.stripeAccountId && (b.paymentIntentId || b.transferGroup) && newPayout > 0) {
                await createLinkedStripeTransfer(stripe, {
                  amountInCents: Math.round(newPayout * 100),
                  destination: caregiverDoc.data().stripeAccountId,
                  paymentIntentId: b.paymentIntentId,
                  transferGroup: b.transferGroup,
                  idempotencyKey: `late_checkin_transfer_${doc.id}`,
                });
              }
              
              await doc.ref.update({ 
                status: "completed", 
                escrowStatus: "released_partial", 
                caregiverPayout: newPayout,
                caregiverCommissionAmount: newCommission,
                cost: newCost
              });
              await addCompletedHours(b.clientId, b.caregiverId, b.slot);
              
            } else {
              // A TIEMPO
              const caregiverDoc = await admin.firestore().collection("caregivers").doc(b.caregiverId).get();
              if (caregiverDoc.data()?.stripeAccountId && (b.paymentIntentId || b.transferGroup) && b.caregiverPayout > 0) {
                await createLinkedStripeTransfer(stripe, {
                  amountInCents: Math.round(b.caregiverPayout * 100),
                  destination: caregiverDoc.data().stripeAccountId,
                  paymentIntentId: b.paymentIntentId,
                  transferGroup: b.transferGroup,
                  idempotencyKey: `auto_release_${doc.id}`,
                });
              }
              await doc.ref.update({ status: "completed", escrowStatus: "released_auto" });
              await addCompletedHours(b.clientId, b.caregiverId, b.slot);
            }
          }
        } catch (e) { console.error("Cron Error processing booking", b.id, e); }
      }
    }
  }
  
  // 2. Manejo de Disputas ignoradas por el cuidador > 24 horas
  const disputes = await admin.firestore().collection("bookings")
    .where("escrowStatus", "==", "disputed")
    .where("disputeEscalated", "==", false).get();
    
  for (const doc of disputes.docs) {
    const b = doc.data();
    if (b.disputeOpenedAt) {
      const openedAt = b.disputeOpenedAt.toDate();
      const timeoutDate = new Date(openedAt.getTime() + (24 * 60 * 60 * 1000));
      
      if (now > timeoutDate) {
         try {
            // Silencio administrativo de 24h -> Devolver 100% al cliente
            const disputeRefund = b.totalPaid || b.cost || 0;
            if (b.paymentIntentId && disputeRefund > 0) {
              await createIdempotentRefund(stripe, {
                paymentIntentId: b.paymentIntentId,
                amountInCents: Math.round(disputeRefund * 100),
                idempotencyKey: `dispute_timeout_refund_${doc.id}`,
              });
            }
            await doc.ref.update({ escrowStatus: "refunded", status: "completed", cancellationReason: "Disputa resuelta a favor del cliente por inactividad del cuidador" });
         } catch(e) { console.error("Error timing out dispute", e); }
      }
    }
  }
  
  // 3. Fallback: Disputas no escaladas sin disputeOpenedAt (Legacy)
  const legacyDisputes = await admin.firestore().collection("bookings")
    .where("escrowStatus", "==", "disputed")
    .get();
    
  for (const doc of legacyDisputes.docs) {
    const b = doc.data();
    if (!b.disputeOpenedAt && !b.disputeEscalated) {
      let dateParts;
      if (b.day.includes('/')) {
        const parts = b.day.split('/');
        dateParts = [parts[2], parts[1], parts[0]]; // [yyyy, mm, dd]
      } else {
        dateParts = b.day.split('-'); // [yyyy, mm, dd]
      }
      const slotParts = b.slot.split('-');
      if (dateParts.length === 3 && slotParts.length === 2) {
        const endParts = slotParts[1].split(':');
        const theoreticalEndTime = new Date(parseInt(dateParts[0]), parseInt(dateParts[1]) - 1, parseInt(dateParts[2]), parseInt(endParts[0]), parseInt(endParts[1]));
        const timeoutDate = new Date(theoreticalEndTime.getTime() + (72 * 60 * 60 * 1000));
        
        if (now > timeoutDate) {
           try {
              const legacyRefund = b.totalPaid || b.cost || 0;
              if (b.paymentIntentId && legacyRefund > 0) {
                await createIdempotentRefund(stripe, {
                  paymentIntentId: b.paymentIntentId,
                  amountInCents: Math.round(legacyRefund * 100),
                  idempotencyKey: `legacy_dispute_refund_${doc.id}`,
                });
              }
              await doc.ref.update({ escrowStatus: "refunded", status: "completed", cancellationReason: "Disputa resuelta por inactividad (Legacy)" });
           } catch(e) { console.error("Error timing out legacy dispute", e); }
        }
      }
    }
  }
  
  return null;
});

exports.adminResolveDispute = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  if (context.auth.token.email !== "maverick6576@gmail.com") throw new functions.https.HttpsError("permission-denied", "Solo administradores.");
  
  const stripe = require("stripe")(stripeSecret.value());
  try {
    const { bookingId, refundToClient, payoutToCaregiver } = data;
    const bookingDoc = await admin.firestore().collection("bookings").doc(bookingId).get();
    if (!bookingDoc.exists) throw new functions.https.HttpsError("not-found", "Booking not found.");
    
    const booking = bookingDoc.data();
    
    if (refundToClient > 0 && booking.paymentIntentId) {
      try {
        await createIdempotentRefund(stripe, {
          paymentIntentId: booking.paymentIntentId,
          amountInCents: Math.round(refundToClient * 100),
          idempotencyKey: `admin_dispute_refund_${bookingId}`,
        });
      } catch(e) {
        console.error("Stripe refund error:", e.message);
      }
    }
    
    if (payoutToCaregiver > 0) {
      const caregiverDoc = await admin.firestore().collection("caregivers").doc(booking.caregiverId).get();
      if (caregiverDoc.data()?.stripeAccountId && (booking.paymentIntentId || booking.transferGroup)) {
         try {
           await createLinkedStripeTransfer(stripe, {
             amountInCents: Math.round(payoutToCaregiver * 100),
             destination: caregiverDoc.data().stripeAccountId,
             paymentIntentId: booking.paymentIntentId,
             transferGroup: booking.transferGroup,
             idempotencyKey: `admin_dispute_transfer_${bookingId}`,
           });
         } catch(e) {
           console.error("Stripe transfer error:", e.message);
         }
      }
    }
    
    await admin.firestore().collection("bookings").doc(bookingId).update({ 
      escrowStatus: "resolved_partial", 
      status: "completed",
      disputeRequested: false,
      caregiverPayout: payoutToCaregiver,
      caregiverCommissionAmount: booking.cost - refundToClient - payoutToCaregiver
    });
    
    await addCompletedHours(booking.clientId, booking.caregiverId, booking.slot);
    
    return { success: true };
  } catch (error) { throw new functions.https.HttpsError("internal", error.message); }
});


exports.processResolutionAgreement = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  try {
    const bookingDoc = await admin.firestore().collection("bookings").doc(data.bookingId).get();
    if (!bookingDoc.exists) throw new functions.https.HttpsError("not-found", "Booking not found.");
    
    const booking = bookingDoc.data();

    // Security check: Only involved parties or admin
    if (booking.clientId !== context.auth.uid && booking.caregiverId !== context.auth.uid) {
      if (context.auth.token.email !== "maverick6576@gmail.com") {
        throw new functions.https.HttpsError("permission-denied", "No autorizado.");
      }
    }

    const caregiverDoc = await admin.firestore().collection("caregivers").doc(booking.caregiverId).get();
    if (booking.paymentIntentId && booking.disputeAmount > 0) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: Math.round(booking.disputeAmount * 100),
        idempotencyKey: `dispute_agree_refund_${data.bookingId}`,
      });
    }
    
    const dineroParaElCuidador = Math.max(0, booking.cost - (booking.disputeAmount || 0));
    const comisionCuidador = dineroParaElCuidador * booking.caregiverCommissionRate;
    const payoutCuidador = dineroParaElCuidador - comisionCuidador;
    
    if (payoutCuidador > 0) {
      if (!caregiverDoc.data()?.stripeAccountId) {
        throw new functions.https.HttpsError("failed-precondition", "El cuidador no tiene cuenta bancaria (Stripe) configurada para recibir el pago.");
      }

      if (booking.paymentIntentId || booking.transferGroup) {
        await createLinkedStripeTransfer(stripe, {
          amountInCents: Math.round(payoutCuidador * 100),
          destination: caregiverDoc.data().stripeAccountId,
          paymentIntentId: booking.paymentIntentId,
          transferGroup: booking.transferGroup,
          idempotencyKey: `dispute_agree_transfer_${data.bookingId}`,
        });
      }
    }
    
    await admin.firestore().collection("bookings").doc(data.bookingId).update({ 
      escrowStatus: "resolved_partial", 
      status: "completed",
      caregiverPayout: payoutCuidador,
      caregiverCommissionAmount: comisionCuidador
    });
    await addCompletedHours(booking.clientId, booking.caregiverId, booking.slot);
    return { success: true };
  } catch (error) { throw new functions.https.HttpsError("internal", error.message); }
});

// --- FCM PUSH NOTIFICATIONS TRIGGERS ---

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");

// Función auxiliar para buscar el token y enviar la notificación
async function sendPushNotification(userId, title, body, dataPayload = {}) {
  try {
    const userDoc = await admin.firestore().collection("users").doc(userId).get();
    if (!userDoc.exists) return;
    
    const fcmToken = userDoc.data().fcmToken;
    if (fcmToken) {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        data: dataPayload,
      });
      console.log(`Push enviada con éxito a ${userId}`);
    } else {
      console.log(`El usuario ${userId} no tiene fcmToken registrado.`);
    }
  } catch (error) {
    console.error(`Error enviando push a ${userId}:`, error);
  }
}

// 1. Nuevo Mensaje de Chat (V2)
exports.pushOnMessageCreated = onDocumentCreated({
  document: "chats/{chatRoomId}/messages/{messageId}",
  region: "europe-west1"
}, async (event) => {
  const message = event.data.data();
  if (!message) return null;
  const roomParts = event.params.chatRoomId.split('_');
  if (roomParts.length !== 2) return null;
  
  const clientId = roomParts[0];
  const caregiverId = roomParts[1];

  // Determinar con certeza el emisor y el receptor
  let senderId = message.senderId;
  let receiverId = message.receiverId;

  if (!senderId) {
    if (message.sender === 'Client') {
      senderId = clientId;
      receiverId = caregiverId;
    } else if (message.sender === 'Caregiver') {
      senderId = caregiverId;
      receiverId = clientId;
    } else {
      senderId = roomParts[0];
      receiverId = roomParts[1];
    }
  }

  if (!receiverId) {
    receiverId = senderId === clientId ? caregiverId : clientId;
  }

  // PROTECCIÓN ABSOLUTA: Si el receptor resulta ser el mismo que el emisor, abortar
  if (receiverId === senderId) {
    console.log(`[pushOnMessageCreated] Se omite push: el destinatario (${receiverId}) es el mismo emisor.`);
    return null;
  }

  // Obtener nombre del remitente para personalizar el título
  let notificationTitle = "Nuevo mensaje de chat";
  try {
    const chatDoc = await admin.firestore().collection("chats").doc(event.params.chatRoomId).get();
    const chatData = chatDoc.exists ? chatDoc.data() : {};
    if (receiverId === caregiverId) {
      notificationTitle = chatData.clientName
        ? `Mensaje de ${chatData.clientName}`
        : "Mensaje de la Familia";
    } else {
      notificationTitle = `Mensaje de ${chatData.caregiverName || "tu cuidador/a"}`;
    }
  } catch (_) {}

  const pushBody = message.isDeleted
    ? "Se ha eliminado un mensaje"
    : (message.text || "Tienes un mensaje nuevo.");

  await sendPushNotification(receiverId, notificationTitle, pushBody, {
    type: "chat",
    chatRoomId: event.params.chatRoomId,
    senderId: senderId
  });
  return null;
});

// 2. Nueva Reserva (Se notifica al cuidador) (V2)
exports.pushOnBookingCreated = onDocumentCreated({
  document: "bookings/{bookingId}",
  region: "europe-west1"
}, async (event) => {
  const booking = event.data.data();
  if (booking.status === "pendingPayment") {
    console.log(`Reserva ${event.params.bookingId} creada en estado pendingPayment. Esperando al pago.`);
    return null;
  }
  await sendPushNotification(
    booking.caregiverId, 
    "¡Nueva Solicitud de Reserva!", 
    `Han solicitado tus servicios para el ${formatDateEs(booking.day)} a las ${booking.slot}.`, 
    { type: "booking", bookingId: event.params.bookingId }
  );
  return null;
});

async function addIncidentToCaregiver(caregiverId) {
  const cgRef = admin.firestore().collection("users").doc(caregiverId);
  const cgDoc = await cgRef.get();
  if (!cgDoc.exists) return;
  
  const now = new Date();
  let incidentDates = cgDoc.data().incidentDates || [];
  incidentDates.push(admin.firestore.Timestamp.fromDate(now));
  
  // Calculate penalties
  const thirtyDaysAgo = new Date(now.getTime() - (30 * 24 * 60 * 60 * 1000));
  const ninetyDaysAgo = new Date(now.getTime() - (90 * 24 * 60 * 60 * 1000));
  
  const incidents30 = incidentDates.filter(d => d.toDate() > thirtyDaysAgo).length;
  const incidents90 = incidentDates.filter(d => d.toDate() > ninetyDaysAgo).length;
  
  let blockedUntil = cgDoc.data().blockedUntil ? cgDoc.data().blockedUntil.toDate() : null;
  let status = cgDoc.data().status || "active";
  
  if (incidents90 > 10) {
    status = "suspended";
    blockedUntil = new Date(now.getTime() + (3650 * 24 * 60 * 60 * 1000)); // 10 years
  } else if (incidents30 > 3) {
    // Only block if not already suspended
    if (status !== "suspended") {
      blockedUntil = new Date(now.getTime() + (5 * 24 * 60 * 60 * 1000)); // 5 days
    }
  }
  
  const updateData = { incidentDates: incidentDates, status: status };
  if (blockedUntil) updateData.blockedUntil = admin.firestore.Timestamp.fromDate(blockedUntil);
  
  await cgRef.update(updateData);
}

// 3. Actualización de Reserva (Confirmación, Cancelación, Pagos y Disputas) (V2)
exports.pushOnBookingUpdated = onDocumentUpdated({
  document: "bookings/{bookingId}",
  region: "europe-west1"
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (before.escrowStatus !== "disputed" && after.escrowStatus === "disputed") {
    // Automáticamente añadir una incidencia al cuidador cuando el cliente abre una disputa
    await addIncidentToCaregiver(after.caregiverId);
    
    // Notificar al cuidador de la disputa
    await sendPushNotification(
      after.caregiverId,
      "Disputa Abierta",
      `El cliente ha abierto una disputa proponiendo un reembolso de ${after.disputeAmount}€. Tienes 24 horas para responder.`,
      { type: "booking", bookingId: event.params.bookingId }
    );
  }

  // Notificaciones de pagos y resolución de disputas
  if (before.escrowStatus !== after.escrowStatus) {
    if ((after.escrowStatus === "released_auto" || after.escrowStatus === "released_manual") && after.checkInTime) {
      await sendPushNotification(
        after.caregiverId,
        "¡Pago Recibido!",
        `Has recibido un pago de ${after.caregiverPayout?.toFixed(2)}€ por el servicio del ${formatDateEs(after.day)}.`,
        { type: "payment", bookingId: event.params.bookingId }
      );
    } 
    else if (after.escrowStatus === "released_partial" && after.checkInTime) {
      await sendPushNotification(
        after.caregiverId,
        "Pago Recibido (Ajustado)",
        `Has recibido un pago de ${after.caregiverPayout?.toFixed(2)}€. Se ha deducido el tiempo de retraso.`,
        { type: "payment", bookingId: event.params.bookingId }
      );
      const refundAmount = after.cost - (after.caregiverPayout + after.caregiverCommissionAmount);
      if (refundAmount > 0) {
        await sendPushNotification(
          after.clientId,
          "Reembolso por Retraso",
          `Hemos procesado un reembolso de ${refundAmount.toFixed(2)}€ a tu método de pago por el retraso del cuidador.`,
          { type: "payment", bookingId: event.params.bookingId }
        );
      }
    }
    else if (after.escrowStatus === "resolved_partial") {
      await sendPushNotification(
        after.caregiverId,
        "Disputa Resuelta",
        `La disputa se ha resuelto y has recibido un pago final de ${after.caregiverPayout?.toFixed(2)}€.`,
        { type: "payment", bookingId: event.params.bookingId }
      );
      await sendPushNotification(
        after.clientId,
        "Disputa Resuelta",
        `Se ha resuelto la disputa y se ha emitido un reembolso a tu método de pago según el acuerdo o resolución.`,
        { type: "payment", bookingId: event.params.bookingId }
      );
    }
    else if (after.escrowStatus === "refunded") {
      await sendPushNotification(
        after.clientId,
        "Reembolso Procesado",
        `Se ha reembolsado el importe completo a tu método de pago por el servicio del ${formatDateEs(after.day)}.`,
        { type: "payment", bookingId: event.params.bookingId }
      );
    }
  }

  if (before.status !== after.status) {
    if (before.status === "pendingPayment" && after.status === "pending") {
      // Notificar al cuidador que se completó el pago y tiene una nueva solicitud
      await sendPushNotification(
        after.caregiverId, 
        "¡Nueva Solicitud de Reserva!", 
        `Han solicitado tus servicios para el ${formatDateEs(after.day)} a las ${after.slot}.`, 
        { type: "booking", bookingId: event.params.bookingId }
      );
    } else if (after.status === "confirmed") {
      // Notificar al cliente que se aceptó
      await sendPushNotification(
        after.clientId, 
        "¡Reserva Confirmada!", 
        `El cuidador ha aceptado tu reserva para el ${formatDateEs(after.day)}.`, 
        { type: "booking", bookingId: event.params.bookingId }
      );
    } else if (after.status === "cancelled" || after.status === "cancelledLate") {
      // Notificar a ambos por si acaso
      await sendPushNotification(after.caregiverId, "Reserva Cancelada", `La reserva del ${formatDateEs(after.day)} ha sido cancelada.`, { type: "booking", bookingId: event.params.bookingId });
      await sendPushNotification(after.clientId, "Reserva Cancelada", `La reserva del ${formatDateEs(after.day)} ha sido cancelada.`, { type: "booking", bookingId: event.params.bookingId });
    }
  }
  return null;
});

// --- STRIPE WEBHOOK ---
exports.stripeWebhook = functions.region("europe-west1").runWith({ secrets: [stripeSecret, webhookSecret] }).https.onRequest(async (req, res) => {
    const stripe = require("stripe")(stripeSecret.value());
    const sig = req.headers["stripe-signature"];
    let event;
    try {
      event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret.value());
    } catch (err) {
      console.error("Webhook Error:", err.message);
      return res.status(400).send(`Webhook Error: ${err.message}`);
    }
  
    if (event.type === "payment_intent.succeeded") {
      const paymentIntent = event.data.object;
      
      try {
        const querySnapshot = await admin.firestore().collection("bookings")
          .where("paymentIntentId", "==", paymentIntent.id).get();
        
        const batch = admin.firestore().batch();
        let totalCalculatedPaid = 0;
        
        // Validation and Sanitization
        for (const doc of querySnapshot.docs) {
          const booking = doc.data();
          
          let trueCost = booking.cost; 
          let trueClientFee = booking.clientFee;
          let trueCommissionAmount = booking.caregiverCommissionAmount;
          let truePayout = booking.caregiverPayout;
          let trueTotalPaid = booking.totalPaid;
          
          // Overwrite with mathematical certainty to prevent spoofing
          trueClientFee = trueCost * 0.10; // Enforce 10% client fee
          trueTotalPaid = trueCost + trueClientFee;
          const commissionRate = booking.caregiverCommissionRate || 0.18;
          trueCommissionAmount = trueCost * commissionRate;
          truePayout = trueCost - trueCommissionAmount;
          
          totalCalculatedPaid += trueTotalPaid;
          
          let newStatus = booking.status === "confirmed" ? "confirmed" : "pending";

          batch.update(doc.ref, {
            status: newStatus,
            clientFee: trueClientFee,
            caregiverCommissionAmount: trueCommissionAmount,
            caregiverPayout: truePayout,
            totalPaid: trueTotalPaid
          });
        }
        
        // Verify payment intent amount covers the bookings
        const expectedCents = Math.round(totalCalculatedPaid * 100);
        if (paymentIntent.amount < expectedCents && querySnapshot.docs.length > 0) {
            console.error(`Fraud detected: Paid ${paymentIntent.amount} but expected ${expectedCents}.`);
            // We could mark them as cancelled or flag them, but for now we won't mark them pending.
            return res.status(200).send("Payment amount insufficient, bookings not confirmed.");
        }
        
        await batch.commit();
        console.log(`Updated and sanitized bookings for PaymentIntent ${paymentIntent.id}`);
      } catch (e) {
        console.error("Error updating bookings:", e);
        return res.status(500).send("Internal Server Error");
      }
    }
  
    res.json({received: true});
});

// 4. Nueva Oferta de Trabajo (Se notifica a los cuidadores)
exports.pushOnJobOfferCreated = onDocumentCreated({
  document: "job_offers/{offerId}",
  region: "europe-west1"
}, async (event) => {
  const offer = event.data.data();
  
  // Vamos a enviar a todos los cuidadores por simplicidad
  const caregiversSnapshot = await admin.firestore().collection("users").where("role", "==", "caregiver").get();
  
  const tokens = [];
  caregiversSnapshot.forEach(doc => {
    const data = doc.data();
    if (data.fcmToken) tokens.push(data.fcmToken);
  });

  if (tokens.length > 0) {
    const title = offer.isUrgent ? "⚡ ¡Nueva Oferta Urgente!" : "Nueva Oferta de Trabajo";
    const body = `Un cliente busca cuidador: ${offer.title}. ¡Aplica ahora!`;
    
    // Send multicast
    await admin.messaging().sendEachForMulticast({
      tokens: tokens,
      notification: { title, body },
      data: { type: "job_offer", offerId: event.params.offerId }
    });
    console.log(`Push enviada a ${tokens.length} cuidadores por la oferta ${event.params.offerId}`);
  }
  return null;
});

// 5. Nueva Solicitud/Contraoferta (Se notifica al cliente)
exports.pushOnApplicationCreated = onDocumentCreated({
  document: "job_offers/{offerId}/applications/{appId}",
  region: "europe-west1"
}, async (event) => {
  const application = event.data.data();
  
  // Obtenemos la oferta para saber quién es el cliente
  const offerDoc = await admin.firestore().collection("job_offers").doc(event.params.offerId).get();
  if (!offerDoc.exists) return null;
  const offer = offerDoc.data();

  await sendPushNotification(
    offer.clientId, 
    "¡Nueva Solicitud Recibida!", 
    `${application.caregiverName} ha aplicado a tu oferta "${offer.title}".`, 
    { type: "job_application", offerId: event.params.offerId, applicationId: event.params.appId }
  );
  return null;
});

// 6. Solicitud Aceptada (Se notifica al cuidador)
exports.pushOnApplicationUpdated = onDocumentUpdated({
  document: "job_offers/{offerId}/applications/{appId}",
  region: "europe-west1"
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (before.status !== "accepted" && after.status === "accepted") {
    const offerDoc = await admin.firestore().collection("job_offers").doc(event.params.offerId).get();
    if (!offerDoc.exists) return null;
    const offer = offerDoc.data();

    await sendPushNotification(
      after.caregiverId, 
      "¡Enhorabuena! Solicitud Aceptada", 
      `El cliente ha aceptado tu perfil para la oferta "${offer.title}".`, 
      { type: "job_application_accepted", offerId: event.params.offerId }
    );
  }
  return null;
});


exports.adminBlockCaregiver = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth || context.auth.token.email !== "maverick6576@gmail.com") throw new functions.https.HttpsError("permission-denied", "Solo administradores.");
  const { caregiverId, days } = data;
  const now = new Date();
  
  const updateData = {};
  if (days >= 365) { 
    updateData.status = "suspended";
    updateData.blockedUntil = admin.firestore.Timestamp.fromDate(new Date(now.getTime() + (3650 * 24 * 60 * 60 * 1000)));
  } else if (days === 0) { 
    updateData.status = "active";
    updateData.blockedUntil = admin.firestore.FieldValue.delete();
  } else { 
    updateData.blockedUntil = admin.firestore.Timestamp.fromDate(new Date(now.getTime() + (days * 24 * 60 * 60 * 1000)));
  }
  
  await admin.firestore().collection("users").doc(caregiverId).update(updateData);
  return { success: true };
});


const { onDocumentDeleted } = require("firebase-functions/v2/firestore");

exports.triggerSyncLastMessageOnDelete = onDocumentDeleted({
  document: "chats/{chatRoomId}/messages/{messageId}",
  region: "europe-west1"
}, async (event) => {
  const chatId = event.params.chatRoomId;
  const messagesRef = admin.firestore().collection(`chats/${chatId}/messages`);
  const lastMsgSnapshot = await messagesRef.orderBy('timestamp', 'desc').limit(1).get();
  
  if (lastMsgSnapshot.empty) {
    await admin.firestore().collection('chats').doc(chatId).update({
      lastMessage: '',
      lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp()
    });
  } else {
    const lastMsgData = lastMsgSnapshot.docs[0].data();
    await admin.firestore().collection('chats').doc(chatId).update({
      lastMessage: lastMsgData.text,
      lastMessageTimestamp: lastMsgData.timestamp
    });
  }
  return null;
});

exports.deleteUserAccountRgpd = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const db = admin.firestore();
  try {
    const batch = db.batch();
    batch.delete(db.collection("users").doc(uid));
    batch.delete(db.collection("clients").doc(uid));
    batch.delete(db.collection("caregivers").doc(uid));
    await batch.commit();
    return { success: true };
  } catch (error) {
    console.error("Error in deleteUserAccountRgpd:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});
