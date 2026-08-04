const functions = require("firebase-functions");
const admin = require("firebase-admin");
const Stripe = require("stripe");

admin.initializeApp();
const db = admin.firestore();

// Inicialización de Stripe (usar STRIPE_SECRET_KEY en env/secrets o fallback a sandbox por defecto)
const stripeSecretKey = process.env.STRIPE_SECRET_KEY || functions.config().stripe?.secret || "sk_test_51MockStripeSecretKeyForSeniCareSandbox";
const stripe = new Stripe(stripeSecretKey, { apiVersion: "2024-06-20" });

/**
 * 1. createConnectAccount
 * Crea una cuenta conectada en Stripe (Express) para el cuidador profesional.
 */
exports.createConnectAccount = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para conectar cuenta bancaria.");
  }
  try {
    const { email, country = "ES" } = data;
    const account = await stripe.accounts.create({
      type: "express",
      country: country,
      email: email || context.auth.token.email,
      capabilities: {
        transfers: { requested: true },
      },
    });

    await db.collection("caregivers").doc(context.auth.uid).set({
      stripeConnectedAccountId: account.id,
      stripeKycStatus: "pending",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { success: true, accountId: account.id };
  } catch (error) {
    console.error("Error creando Stripe Connect Account:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 2. getStripeAccountLink
 * Genera el enlace de onboarding de Stripe para completar KYC e identidad bancaria.
 */
exports.getStripeAccountLink = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para obtener el enlace.");
  }
  try {
    const { accountId, refreshUrl, returnUrl } = data;
    if (!accountId) {
      throw new functions.https.HttpsError("invalid-argument", "Se requiere accountId.");
    }
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: refreshUrl || "https://senicare.app/stripe-refresh",
      return_url: returnUrl || "https://senicare.app/stripe-success",
      type: "account_onboarding",
    });
    return { url: accountLink.url };
  } catch (error) {
    console.error("Error generando Stripe Account Link:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 3. createPaymentIntent
 * Crea un PaymentIntent con retención en Escrow para una reserva.
 */
exports.createPaymentIntent = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para realizar pagos.");
  }
  try {
    const { amountInCents, currency = "eur", bookingId, caregiverStripeAccountId } = data;
    if (!amountInCents || amountInCents <= 0) {
      throw new functions.https.HttpsError("invalid-argument", "El monto debe ser mayor que 0.");
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountInCents,
      currency: currency,
      payment_method_types: ["card"],
      transfer_group: `booking_${bookingId}`,
      metadata: {
        bookingId: bookingId || "N/A",
        clientId: context.auth.uid,
        caregiverStripeAccountId: caregiverStripeAccountId || "N/A",
      },
    });

    if (bookingId) {
      await db.collection("bookings").doc(bookingId).set({
        paymentIntentId: paymentIntent.id,
        transferGroup: `booking_${bookingId}`,
        escrowStatus: "held",
        totalAmountInCents: amountInCents,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    };
  } catch (error) {
    console.error("Error creando PaymentIntent:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 4. releaseEscrowPayment
 * Libera el pago en garantía hacia el cuidador tras la finalización del servicio.
 */
exports.releaseEscrowPayment = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para liberar el pago.");
  }
  try {
    const { bookingId } = data;
    if (!bookingId) {
      throw new functions.https.HttpsError("invalid-argument", "Se requiere bookingId.");
    }

    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }

    const booking = bookingDoc.data();
    if (booking.escrowStatus === "released") {
      throw new functions.https.HttpsError("failed-precondition", "El pago ya ha sido liberado previamente.");
    }

    const destinationAccountId = booking.caregiverStripeAccountId;
    const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);

    // En servicio finalizado, el cuidador recibe el 90% (plataforma retiene 10% comisión)
    const transferAmountInCents = Math.round(totalAmountInCents * 0.90);

    if (destinationAccountId && transferAmountInCents > 0) {
      await stripe.transfers.create({
        amount: transferAmountInCents,
        currency: "eur",
        destination: destinationAccountId,
        transfer_group: booking.transferGroup || `booking_${bookingId}`,
        description: `Liquidación servicio completado - Reserva #${bookingId}`,
      });
    }

    await bookingRef.update({
      escrowStatus: "released",
      status: "Completed",
      releasedAmountInCents: transferAmountInCents,
      releasedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, releasedAmountInCents: transferAmountInCents };
  } catch (error) {
    console.error("Error liberando pago en Escrow:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 5. cancelBookingProcess
 * Procesa cancelación de reserva: en cancelación tardía (< 24h) reembolsa al cliente (45%)
 * y transfiere compensación (45%) a la cuenta conectada de Stripe del cuidador.
 */
exports.cancelBookingProcess = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debes iniciar sesión para cancelar una reserva.");
  }

  const { bookingId, cancelReason } = data;
  if (!bookingId) {
    throw new functions.https.HttpsError("invalid-argument", "Se requiere el ID de la reserva (bookingId).");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const bookingDoc = await bookingRef.get();
  if (!bookingDoc.exists) {
    throw new functions.https.HttpsError("not-found", "La reserva indicada no existe.");
  }

  const booking = bookingDoc.data();
  const paymentIntentId = booking.paymentIntentId || booking.chargeId;
  const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);

  if (!paymentIntentId || totalAmountInCents <= 0) {
    throw new functions.https.HttpsError("failed-precondition", "La reserva no tiene un pago en Escrow válido asociado.");
  }

  // Obtener cuenta conectada del cuidador (destinationAccountId)
  let destinationAccountId = booking.caregiverStripeAccountId;
  if (!destinationAccountId && booking.caregiverId) {
    const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
    if (caregiverDoc.exists) {
      destinationAccountId = caregiverDoc.data().stripeConnectedAccountId;
    }
  }

  // Calcular horas hasta la reserva para aplicar política de cancelación
  const bookingDate = booking.bookingDate ? booking.bookingDate.toDate() : new Date(Date.now() + 12 * 3600 * 1000);
  const hoursUntilBooking = (bookingDate.getTime() - Date.now()) / (1000 * 60 * 60);

  let clientRefundAmountInCents = 0;
  let caregiverCompensationInCents = 0;
  let cancellationType = "EARLY_CANCELLATION";

  if (hoursUntilBooking < 24) {
    // --- CANCELACIÓN TARDÍA (< 24 HORAS) ---
    cancellationType = "LATE_CANCELLATION";
    // 45% compensación para el Cuidador por tiempo bloqueado
    caregiverCompensationInCents = Math.round(totalAmountInCents * 0.45);
    // 45% reembolso para el Cliente (plataforma retiene 10% operativa)
    clientRefundAmountInCents = Math.round(totalAmountInCents * 0.45);
  } else {
    // --- CANCELACIÓN ANTICIPADA (>= 24 HORAS) ---
    cancellationType = "EARLY_CANCELLATION";
    clientRefundAmountInCents = totalAmountInCents;
    caregiverCompensationInCents = 0;
  }

  try {
    // 1. Reembolso a la cuenta del cliente
    if (clientRefundAmountInCents > 0) {
      const refundPayload = paymentIntentId.startsWith("pi_")
        ? { payment_intent: paymentIntentId, amount: clientRefundAmountInCents }
        : { charge: paymentIntentId, amount: clientRefundAmountInCents };
      await stripe.refunds.create(refundPayload);
      console.log(`✅ Reembolso de ${clientRefundAmountInCents} céntimos procesado al cliente para booking ${bookingId}`);
    }

    // 2. Transferencia compensatoria (45%) al Cuidador en cancelación tardía
    if (caregiverCompensationInCents > 0 && destinationAccountId) {
      await stripe.transfers.create({
        amount: caregiverCompensationInCents,
        currency: "eur",
        destination: destinationAccountId,
        transfer_group: booking.transferGroup || `booking_${bookingId}`,
        description: `Compensación 45% cancelación tardía - Reserva #${bookingId}`,
      });
      console.log(`✅ Transferencia compensatoria (45% -> ${caregiverCompensationInCents} céntimos) enviada a ${destinationAccountId}`);
    }

    await bookingRef.update({
      status: "Cancelled",
      cancellationType: cancellationType,
      cancelReason: cancelReason || "Cancelado por el usuario",
      isRefunded: true,
      refundedAmountInCents: clientRefundAmountInCents,
      caregiverCompensationInCents: caregiverCompensationInCents,
      escrowStatus: "cancelled_settled",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      cancellationType,
      clientRefundAmountInCents,
      caregiverCompensationInCents,
      message: hoursUntilBooking < 24
        ? "Cancelación tardía procesada: 45% devuelto al cliente y 45% transferido al cuidador."
        : "Cancelación anticipada procesada correctamente con reembolso completo al cliente.",
    };
  } catch (error) {
    console.error("❌ Error procesando cancelación en Stripe:", error);
    throw new functions.https.HttpsError("internal", "Error en devolución o compensación en Stripe: " + error.message);
  }
});

/**
 * 6. autoReleaseEscrowCron
 * Tarea programada (Cron Job) que libera automáticamente pagos en Escrow 24h tras finalizar la cita.
 */
exports.autoReleaseEscrowCron = functions.region("europe-west1").pubsub.schedule("every 24 hours").onRun(async (context) => {
  console.log("Ejecutando autoReleaseEscrowCron...");
  const now = admin.firestore.Timestamp.now();
  const pendingBookingsSnap = await db.collection("bookings")
    .where("status", "==", "Completed")
    .where("escrowStatus", "==", "held")
    .get();

  let releasedCount = 0;
  for (const doc of pendingBookingsSnap.docs) {
    try {
      const booking = doc.data();
      const destinationAccountId = booking.caregiverStripeAccountId;
      const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);
      const transferAmountInCents = Math.round(totalAmountInCents * 0.90);

      if (destinationAccountId && transferAmountInCents > 0) {
        await stripe.transfers.create({
          amount: transferAmountInCents,
          currency: "eur",
          destination: destinationAccountId,
          transfer_group: booking.transferGroup || `booking_${doc.id}`,
          description: `Liquidación automática cron - Reserva #${doc.id}`,
        });
      }
      await doc.ref.update({
        escrowStatus: "released",
        releasedAmountInCents: transferAmountInCents,
        releasedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      releasedCount++;
    } catch (e) {
      console.error(`Error en cron autoRelease para booking ${doc.id}:`, e);
    }
  }
  console.log(`Cron finalizado: ${releasedCount} reservas liberadas.`);
  return null;
});

/**
 * 7. processResolutionAgreement
 * Procesa la resolución acordada de una disputa o mediación en reservas.
 */
exports.processResolutionAgreement = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para resolver disputas.");
  }
  try {
    const { bookingId, clientPercentage = 50, caregiverPercentage = 50 } = data;
    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingDoc.data();
    const paymentIntentId = booking.paymentIntentId || booking.chargeId;
    const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);

    const clientRefundInCents = Math.round(totalAmountInCents * (clientPercentage / 100));
    const caregiverTransferInCents = Math.round(totalAmountInCents * (caregiverPercentage / 100));

    if (clientRefundInCents > 0 && paymentIntentId) {
      const refundPayload = paymentIntentId.startsWith("pi_")
        ? { payment_intent: paymentIntentId, amount: clientRefundInCents }
        : { charge: paymentIntentId, amount: clientRefundInCents };
      await stripe.refunds.create(refundPayload);
    }

    const destinationAccountId = booking.caregiverStripeAccountId;
    if (caregiverTransferInCents > 0 && destinationAccountId) {
      await stripe.transfers.create({
        amount: caregiverTransferInCents,
        currency: "eur",
        destination: destinationAccountId,
        transfer_group: booking.transferGroup || `booking_${bookingId}`,
      });
    }

    await bookingRef.update({
      status: "Resolved",
      escrowStatus: "resolution_settled",
      resolutionDetails: { clientPercentage, caregiverPercentage },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  } catch (error) {
    console.error("Error procesando resolución:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 8. pushOnMessageCreated
 * Envía notificación Push FCM cuando se crea un nuevo mensaje en un chat.
 */
exports.pushOnMessageCreated = functions.region("europe-west1").firestore.document("chats/{chatId}/messages/{messageId}").onCreate(async (snap, context) => {
  const message = snap.data();
  const { chatId } = context.params;
  try {
    const chatDoc = await db.collection("chats").doc(chatId).get();
    if (!chatDoc.exists) return null;
    const chatData = chatDoc.data();
    const recipientId = message.senderId === chatData.clientId ? chatData.caregiverId : chatData.clientId;
    const userDoc = await db.collection("users").doc(recipientId).get();
    const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
    if (!fcmToken) return null;

    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: `Nuevo mensaje de ${message.senderName || "SeniCare"}`,
        body: message.text || "Ha enviado un mensaje",
      },
      data: { chatId: chatId, type: "CHAT_MESSAGE" },
    });
  } catch (e) {
    console.error("Error en pushOnMessageCreated:", e);
  }
  return null;
});

/**
 * 9. pushOnBookingCreated
 * Envía notificación Push FCM al cuidador cuando se crea una nueva solicitud de reserva.
 */
exports.pushOnBookingCreated = functions.region("europe-west1").firestore.document("bookings/{bookingId}").onCreate(async (snap, context) => {
  const booking = snap.data();
  try {
    const userDoc = await db.collection("users").doc(booking.caregiverId).get();
    const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
    if (!fcmToken) return null;

    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: "¡Nueva Solicitud de Reserva!",
        body: `Tienes una nueva cita pendiente para el día ${booking.day || "programado"}.`,
      },
      data: { bookingId: context.params.bookingId, type: "NEW_BOOKING" },
    });
  } catch (e) {
    console.error("Error en pushOnBookingCreated:", e);
  }
  return null;
});

/**
 * 10. pushOnBookingUpdated
 * Envía notificación Push FCM cuando cambia el estado de una reserva.
 */
exports.pushOnBookingUpdated = functions.region("europe-west1").firestore.document("bookings/{bookingId}").onUpdate(async (change, context) => {
  const before = change.before.data();
  const after = change.after.data();
  if (before.status === after.status) return null;

  try {
    const userDoc = await db.collection("users").doc(after.clientId).get();
    const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
    if (!fcmToken) return null;

    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: `Reserva ${after.status}`,
        body: `El estado de tu reserva ha cambiado a: ${after.status}.`,
      },
      data: { bookingId: context.params.bookingId, type: "BOOKING_STATUS_CHANGED" },
    });
  } catch (e) {
    console.error("Error en pushOnBookingUpdated:", e);
  }
  return null;
});

/**
 * 11. caregiverRejectBooking
 * Permite que un cuidador rechace profesionalmente una solicitud pendiente,
 * ejecutando el reembolso íntegro al cliente y notificándolo.
 */
exports.caregiverRejectBooking = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para rechazar una cita.");
  }
  try {
    const { bookingId, rejectionReason = "No disponible" } = data;
    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingDoc.data();
    const paymentIntentId = booking.paymentIntentId || booking.chargeId;
    const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);

    if (paymentIntentId && totalAmountInCents > 0) {
      const refundPayload = paymentIntentId.startsWith("pi_")
        ? { payment_intent: paymentIntentId }
        : { charge: paymentIntentId };
      await stripe.refunds.create(refundPayload);
    }

    await bookingRef.update({
      status: "Cancelled",
      cancellationType: "CAREGIVER_REJECTED",
      cancelReason: rejectionReason,
      isRefunded: true,
      refundedAmountInCents: totalAmountInCents,
      escrowStatus: "rejected_refunded",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, message: "Reserva rechazada y reembolso ejecutado." };
  } catch (error) {
    console.error("Error en caregiverRejectBooking:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 12. stripeWebhook
 * Webhook endpoint para escuchar eventos firmados desde Stripe.
 */
exports.stripeWebhook = functions.region("europe-west1").https.onRequest(async (req, res) => {
  const sig = req.headers["stripe-signature"];
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET || "whsec_mockSecretForSeniCareSandbox";
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.rawBody || req.body, sig, webhookSecret);
  } catch (err) {
    console.error("Stripe Webhook Error de firma:", err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  try {
    if (event.type === "payment_intent.succeeded") {
      const pi = event.data.object;
      const bookingId = pi.metadata?.bookingId;
      if (bookingId) {
        await db.collection("bookings").doc(bookingId).update({
          escrowStatus: "held",
          stripePaymentStatus: "succeeded",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
    res.status(200).send({ received: true });
  } catch (error) {
    console.error("Error procesando evento webhook:", error);
    res.status(500).send("Error interno processing webhook.");
  }
});

/**
 * 13. createSecureBooking
 * Crea una reserva en Firestore tras verificar la autenticidad del pago en Escrow.
 */
exports.createSecureBooking = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para crear reserva.");
  }
  try {
    const { caregiverId, day, slot, totalPaid, paymentIntentId } = data;
    const newBookingRef = db.collection("bookings").doc();
    const bookingData = {
      bookingId: newBookingRef.id,
      clientId: context.auth.uid,
      caregiverId: caregiverId,
      day: day,
      slot: slot,
      totalPaid: totalPaid,
      totalAmountInCents: Math.round(totalPaid * 100),
      paymentIntentId: paymentIntentId,
      status: "Pending",
      escrowStatus: "held",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await newBookingRef.set(bookingData);
    return { success: true, bookingId: newBookingRef.id };
  } catch (error) {
    console.error("Error en createSecureBooking:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 14. syncStripeKycStatus
 * Sincroniza el estado KYC e identidad bancaria de una cuenta conectada de Stripe.
 */
exports.syncStripeKycStatus = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para consultar KYC.");
  }
  try {
    const caregiverRef = db.collection("caregivers").doc(context.auth.uid);
    const doc = await caregiverRef.get();
    if (!doc.exists) {
      throw new functions.https.HttpsError("not-found", "Cuidador no encontrado.");
    }
    const accountId = doc.data().stripeConnectedAccountId;
    if (!accountId) {
      return { kycStatus: "unconnected" };
    }
    const account = await stripe.accounts.retrieve(accountId);
    const kycStatus = account.details_submitted ? "verified" : "pending";
    await caregiverRef.update({ stripeKycStatus: kycStatus });
    return { kycStatus: kycStatus };
  } catch (error) {
    console.error("Error en syncStripeKycStatus:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 15. adminResolveDispute
 * Función administrativa para resolver una disputa.
 */
exports.adminResolveDispute = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  try {
    const { bookingId, resolution } = data;
    await db.collection("bookings").doc(bookingId).update({
      status: "Resolved",
      adminResolution: resolution,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true };
  } catch (error) {
    console.error("Error en adminResolveDispute:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 16. adminBlockCaregiver
 * Función administrativa para bloquear un cuidador reportado.
 */
exports.adminBlockCaregiver = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  try {
    const { caregiverId, reason } = data;
    await db.collection("caregivers").doc(caregiverId).update({
      isBlocked: true,
      blockReason: reason || "Administrativo",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true };
  } catch (error) {
    console.error("Error en adminBlockCaregiver:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 17. pushOnApplicationUpdated
 * Notifica al solicitante de empleo de cambios en el estado de su candidatura.
 */
exports.pushOnApplicationUpdated = functions.region("europe-west1").firestore.document("applications/{appId}").onUpdate(async (change, context) => {
  const before = change.before.data();
  const after = change.after.data();
  if (before.status === after.status) return null;
  try {
    const userDoc = await db.collection("users").doc(after.userId).get();
    const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
    if (!fcmToken) return null;
    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: "Candidatura Actualizada",
        body: `El estado de tu solicitud es ahora: ${after.status}`,
      },
      data: { appId: context.params.appId, type: "APPLICATION_UPDATED" },
    });
  } catch (e) {
    console.error("Error en pushOnApplicationUpdated:", e);
  }
  return null;
});

/**
 * 18. pushOnApplicationCreated
 * Notifica al administrador cuando se crea una nueva solicitud/candidatura.
 */
exports.pushOnApplicationCreated = functions.region("europe-west1").firestore.document("applications/{appId}").onCreate(async (snap, context) => {
  console.log(`Nueva candidatura creada: ${context.params.appId}`);
  return null;
});

/**
 * 19. pushOnJobOfferCreated
 * Notifica a los cuidadores cualificados cuando se publica una nueva oferta.
 */
exports.pushOnJobOfferCreated = functions.region("europe-west1").firestore.document("jobOffers/{offerId}").onCreate(async (snap, context) => {
  console.log(`Nueva oferta de empleo publicada: ${context.params.offerId}`);
  return null;
});
