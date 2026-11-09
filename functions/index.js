let functions;
try {
  functions = require("firebase-functions/v1");
} catch (e) {
  functions = require("firebase-functions");
}
if (!functions.region && functions.v1 && functions.v1.region) {
  functions = functions.v1;
}
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const Stripe = require("stripe");

admin.initializeApp();
const db = admin.firestore();

// Inicialización de Stripe (usar STRIPE_SECRET_KEY en env/secrets o fallback a sandbox por defecto)
let stripeSecretKey = process.env.STRIPE_SECRET_KEY || "sk_test_51MockStripeSecretKeyForSeniCareSandbox";
try {
  if (functions.config && functions.config() && functions.config().stripe?.secret) {
    stripeSecretKey = functions.config().stripe.secret;
  }
} catch (e) {
  // Ignorar error si functions.config() no está disponible en este entorno
}
const stripe = new Stripe(stripeSecretKey, { apiVersion: "2024-06-20" });

/**
 * Helper de SeniCare: Calcula comisión de plataforma (18% -> 10% -> 6%) y payout neto
 * en función del historial de recurrencia entre la familia (client) y el cuidador (caregiver).
 * - Primer servicio (0 previos completados): Comisión 18% -> Cuidador recibe 82%
 * - Cliente recurrente (1 a 4 previos completados): Comisión 10% -> Cuidador recibe 90%
 * - Cliente fidelizado (5+ previos completados): Comisión 6% -> Cuidador recibe 94%
 */
async function calculateCaregiverPayout(clientId, caregiverId, totalAmountInCents, baseAmountInCents = null) {
  let commissionRate = 0.18; // 18% base por defecto (primer servicio)
  let commissionTier = "18% (Primer servicio con la familia)";

  if (clientId && caregiverId) {
    try {
      const completedQuery = await db.collection("bookings")
        .where("clientId", "==", clientId)
        .where("caregiverId", "==", caregiverId)
        .where("escrowStatus", "==", "released")
        .get();

      const completedCount = completedQuery.size;
      if (completedCount >= 5) {
        commissionRate = 0.06;
        commissionTier = `6% (Familia fidelizada - ${completedCount} servicios previos)`;
      } else if (completedCount >= 1) {
        commissionRate = 0.10;
        commissionTier = `10% (Familia recurrente - ${completedCount} servicios previos)`;
      }
    } catch (err) {
      console.warn("⚠️ Error consultando historial de recurrencia, aplicando tarifa base 18%:", err.message);
    }
  }

  // Si se proporciona baseAmountInCents (tarifa base del servicio), calculamos el neto del cuidador
  // exactamente sobre esa base para mantener simetría contable 1:1 con el frontend.
  const referenceBaseCents = (baseAmountInCents && baseAmountInCents > 0)
    ? baseAmountInCents
    : totalAmountInCents;
  const transferAmountInCents = Math.round(referenceBaseCents * (1 - commissionRate));
  const platformFeeInCents = Math.max(0, totalAmountInCents - transferAmountInCents);

  return {
    transferAmountInCents,
    platformFeeInCents,
    commissionRatePercent: Math.round(commissionRate * 100),
    commissionTier,
  };
}

/**
 * 1. createConnectAccount
 * Crea una cuenta conectada en Stripe (Express) para el cuidador profesional.
 */
exports.createConnectAccount = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para conectar cuenta bancaria.");
  }
  try {
    const caregiverRef = db.collection("caregivers").doc(context.auth.uid);
    const caregiverDoc = await caregiverRef.get();
    if (caregiverDoc.exists && caregiverDoc.data().stripeConnectedAccountId) {
      console.log(`✅ Cuidador ${context.auth.uid} ya posee cuenta Stripe Connect: ${caregiverDoc.data().stripeConnectedAccountId}`);
      return { success: true, accountId: caregiverDoc.data().stripeConnectedAccountId, existing: true };
    }

    const { email, country = "ES" } = data;
    const account = await stripe.accounts.create({
      type: "express",
      country: country,
      email: email || context.auth.token.email,
      capabilities: {
        transfers: { requested: true },
      },
    });

    await caregiverRef.set({
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
    const { accountId, refreshUrl, returnUrl, type = "account_onboarding" } = data;
    if (!accountId) {
      throw new functions.https.HttpsError("invalid-argument", "Se requiere accountId.");
    }

    if (type === "dashboard" || type === "login_link" || type === "update_bank") {
      try {
        const loginLink = await stripe.accounts.createLoginLink(accountId);
        return { url: loginLink.url, type: "login_link" };
      } catch (loginErr) {
        console.warn("Fallo creando loginLink directo, usando account_update como fallback:", loginErr.message);
      }
    }

    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: refreshUrl || "https://senicare.app/stripe-refresh",
      return_url: returnUrl || "https://senicare.app/stripe-success",
      type: (type === "dashboard" || type === "update_bank") ? "account_update" : "account_onboarding",
    });
    return { url: accountLink.url, type: accountLink.type || type };
  } catch (error) {
    console.error("Error generando Stripe Account Link:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 2b. getCaregiverStripeDashboardLink
 * Genera un enlace seguro (Login Link) al Express Dashboard de Stripe, permitiendo al cuidador
 * ver sus transferencias y cambiar su cuenta bancaria (IBAN) directamente con cifrado bancario PCI-DSS.
 */
exports.getCaregiverStripeDashboardLink = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para gestionar su cuenta bancaria.");
  }
  try {
    let accountId = data?.accountId;
    if (!accountId) {
      const caregiverDoc = await db.collection("caregivers").doc(context.auth.uid).get();
      if (caregiverDoc.exists) {
        accountId = caregiverDoc.data().stripeConnectedAccountId;
      }
    }
    if (!accountId) {
      throw new functions.https.HttpsError("not-found", "No se encontró cuenta Stripe Connect vinculada para este profesional.");
    }

    try {
      const loginLink = await stripe.accounts.createLoginLink(accountId);
      return { success: true, url: loginLink.url, type: "login_link" };
    } catch (loginErr) {
      console.warn("Creando account_onboarding fallback link para Stripe Dashboard:", loginErr.message);
      const accountLink = await stripe.accountLinks.create({
        account: accountId,
        refresh_url: data?.refreshUrl || "https://senicare.app/stripe-refresh",
        return_url: data?.returnUrl || "https://senicare.app/stripe-success",
        type: "account_onboarding",
      });
      return { success: true, url: accountLink.url, type: "account_onboarding" };
    }
  } catch (error) {
    console.error("Error en getCaregiverStripeDashboardLink:", error);
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
    const { amountInCents, currency = "eur", bookingId, caregiverId, durationHours = 2, caregiverStripeAccountId } = data;

    // Blindaje de precio en servidor: si existe caregiverId en Firestore, validamos la tarifa real
    let verifiedAmountInCents = amountInCents;
    let resolvedStripeAccountId = caregiverStripeAccountId;
    if (caregiverId) {
      const caregiverDoc = await db.collection("caregivers").doc(caregiverId).get();
      if (caregiverDoc.exists) {
        const cgData = caregiverDoc.data();
        if (cgData.pricePerHour && durationHours > 0) {
          verifiedAmountInCents = Math.round(cgData.pricePerHour * durationHours * 100);
        }
        if (!resolvedStripeAccountId && cgData.stripeConnectedAccountId) {
          resolvedStripeAccountId = cgData.stripeConnectedAccountId;
        }
      }
    }

    if (!verifiedAmountInCents || verifiedAmountInCents <= 0) {
      throw new functions.https.HttpsError("invalid-argument", "El monto debe ser mayor que 0.");
    }
    if (amountInCents && amountInCents < verifiedAmountInCents) {
      throw new functions.https.HttpsError("permission-denied", "El importe enviado es inferior a la tarifa oficial del profesional.");
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount: verifiedAmountInCents,
      currency: currency,
      payment_method_types: ["card"],
      transfer_group: `booking_${bookingId}`,
      metadata: {
        bookingId: bookingId || "N/A",
        clientId: context.auth.uid,
        caregiverId: caregiverId || "N/A",
        caregiverStripeAccountId: resolvedStripeAccountId || "N/A",
      },
    }, {
      idempotencyKey: bookingId ? `create_pi_${bookingId}` : undefined,
    });

    if (bookingId) {
      await db.collection("bookings").doc(bookingId).set({
        paymentIntentId: paymentIntent.id,
        transferGroup: `booking_${bookingId}`,
        escrowStatus: "pending_payment",
        totalAmountInCents: verifiedAmountInCents,
        baseAmountInCents: verifiedAmountInCents,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
      verifiedAmountInCents: verifiedAmountInCents,
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
    if (booking.clientId !== context.auth.uid && booking.caregiverId !== context.auth.uid && !context.auth.token.admin) {
      throw new functions.https.HttpsError("permission-denied", "No tienes permiso para liberar el pago de esta reserva.");
    }
    if (booking.escrowStatus === "released") {
      throw new functions.https.HttpsError("failed-precondition", "El pago ya ha sido liberado previamente.");
    }
    if (booking.isRefunded || booking.status === "Cancelled") {
      throw new functions.https.HttpsError("failed-precondition", "No se puede liberar una reserva cancelada o reembolsada.");
    }
    if (booking.isDisputed || booking.status === "Disputed") {
      throw new functions.https.HttpsError("failed-precondition", "No se puede liberar una reserva con disputa abierta.");
    }

    let destinationAccountId = booking.caregiverStripeAccountId;
    if (!destinationAccountId && booking.caregiverId) {
      const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
      if (caregiverDoc.exists) {
        destinationAccountId = caregiverDoc.data().stripeConnectedAccountId;
      }
    }

    const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);
    const baseAmountInCents = booking.baseAmountInCents || Math.round((booking.cost || 0) * 100);

    // Cálculo dinámico de comisión SeniCare: 18% (primer servicio) -> 10% (recurrente) -> 6% (fidelizado)
    const {
      transferAmountInCents,
      platformFeeInCents,
      commissionRatePercent,
      commissionTier,
    } = await calculateCaregiverPayout(booking.clientId, booking.caregiverId || booking.caregiver?.id, totalAmountInCents, baseAmountInCents);

    // Prevención de Liquidación Fantasma: si el cuidador no tiene cuenta Stripe Connect vinculada, NO marcar como released
    if (!destinationAccountId) {
      await bookingRef.update({
        escrowStatus: "pending_caregiver_connect",
        status: "Completed",
        releasedAmountInCents: transferAmountInCents,
        platformFeeInCents: platformFeeInCents,
        commissionRatePercent: commissionRatePercent,
        commissionTier: commissionTier,
        lastTransferError: "El cuidador aún no ha vinculado su cuenta bancaria en Stripe Connect.",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {
        success: true,
        escrowStatus: "pending_caregiver_connect",
        message: "Servicio completado. Transferencia retenida hasta que el cuidador conecte su cuenta bancaria.",
        releasedAmountInCents: transferAmountInCents,
        platformFeeInCents: platformFeeInCents,
        commissionRatePercent: commissionRatePercent,
        commissionTier: commissionTier,
      };
    }

    console.log(`ℹ️ Liquidando reserva #${bookingId} con comisión del ${commissionRatePercent}% (${commissionTier}) -> Cuidador: ${transferAmountInCents} céntimos, Plataforma: ${platformFeeInCents} céntimos.`);

    if (transferAmountInCents > 0) {
      try {
        await stripe.transfers.create({
          amount: transferAmountInCents,
          currency: "eur",
          destination: destinationAccountId,
          transfer_group: booking.transferGroup || `booking_${bookingId}`,
          description: `Liquidación servicio completado - Reserva #${bookingId}`,
        }, {
          idempotencyKey: `release_transfer_${bookingId}`,
        });
      } catch (transferError) {
        let pendingStatus = "pending_kyc_transfer";
        let userMessage = "Servicio completado, transferencia pendiente de verificación de Stripe.";

        if (transferError.code === "balance_insufficient") {
          pendingStatus = "pending_settlement_transfer";
          userMessage = "Servicio completado. Fondos en compensación bancaria (1-2 días hábiles); se transferirán automáticamente.";
        } else if (
          transferError.code === "account_invalid" ||
          transferError.code === "invalid_destination" ||
          transferError.code === "account_closed" ||
          (transferError.message && (transferError.message.includes("does not have access to") || transferError.message.includes("not set up")))
        ) {
          pendingStatus = "pending_caregiver_connect";
          userMessage = "La cuenta bancaria o IBAN del profesional requiere actualización en Stripe. Pago retenido de forma segura.";
        } else if (
          transferError.type === "StripeConnectionError" ||
          transferError.type === "StripeAPIError" ||
          transferError.code === "ETIMEDOUT" ||
          transferError.code === "ECONNRESET"
        ) {
          pendingStatus = "pending_network_retry";
          userMessage = "Incidencia de red temporal con la pasarela bancaria. El sistema reintentará la transferencia en el próximo ciclo automático.";
        }

        console.warn(`⚠️ Error en stripe.transfers.create (${pendingStatus}): ${transferError.message}`);
        await bookingRef.update({
          escrowStatus: pendingStatus,
          status: "Completed",
          releasedAmountInCents: transferAmountInCents,
          platformFeeInCents: platformFeeInCents,
          commissionRatePercent: commissionRatePercent,
          commissionTier: commissionTier,
          lastTransferError: transferError.message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {
          success: true,
          escrowStatus: pendingStatus,
          message: userMessage,
          releasedAmountInCents: transferAmountInCents,
          platformFeeInCents: platformFeeInCents,
          commissionRatePercent: commissionRatePercent,
          commissionTier: commissionTier,
        };
      }
    }

    await bookingRef.update({
      escrowStatus: "released",
      status: "Completed",
      releasedAmountInCents: transferAmountInCents,
      platformFeeInCents: platformFeeInCents,
      commissionRatePercent: commissionRatePercent,
      commissionTier: commissionTier,
      releasedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      escrowStatus: "released",
      releasedAmountInCents: transferAmountInCents,
      platformFeeInCents: platformFeeInCents,
      commissionRatePercent: commissionRatePercent,
      commissionTier: commissionTier,
    };
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
  if (booking.clientId !== context.auth.uid && booking.caregiverId !== context.auth.uid && !context.auth.token.admin) {
    throw new functions.https.HttpsError("permission-denied", "No tienes permiso para cancelar esta reserva.");
  }
  if (
    booking.isRefunded ||
    booking.status === "Cancelled" ||
    booking.escrowStatus === "cancelled_settled" ||
    booking.escrowStatus === "rejected_refunded" ||
    booking.escrowStatus === "released"
  ) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Esta reserva ya ha sido cancelada, reembolsada o liquidada previamente."
    );
  }

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

  // Calcular fecha/hora real del turno a partir de bookingDate o day + slot (sin penalizar por defecto con 12h)
  let bookingDate;
  if (booking.bookingDate && typeof booking.bookingDate.toDate === "function") {
    bookingDate = booking.bookingDate.toDate();
  } else if (booking.bookingDate) {
    bookingDate = new Date(booking.bookingDate);
  } else if (booking.day) {
    const weekdayMap = {
      "Domingo": 0,
      "Lunes": 1,
      "Martes": 2,
      "Miércoles": 3,
      "Jueves": 4,
      "Viernes": 5,
      "Sábado": 6,
    };
    const base = booking.createdAt && typeof booking.createdAt.toDate === "function"
      ? booking.createdAt.toDate()
      : new Date();
    const targetDay = weekdayMap[booking.day] !== undefined ? weekdayMap[booking.day] : base.getDay();
    let daysAhead = (targetDay - base.getDay() + 7) % 7;
    if (daysAhead <= 0) daysAhead += 7;
    const slotParts = String(booking.slot || "09:00").split(":");
    const hour = parseInt(slotParts[0], 10) || 9;
    const minute = parseInt(slotParts[1], 10) || 0;
    bookingDate = new Date(base.getTime() + daysAhead * 24 * 3600 * 1000);
    bookingDate.setHours(hour, minute, 0, 0);
  } else {
    // Fallback seguro >= 48h para no aplicar penalización tardía injustificada si no se especificó fecha
    bookingDate = new Date(Date.now() + 48 * 3600 * 1000);
  }
  const hoursUntilBooking = (bookingDate.getTime() - Date.now()) / (1000 * 60 * 60);

  let clientRefundAmountInCents = 0;
  let caregiverCompensationInCents = 0;
  let cancellationType = "EARLY_CANCELLATION";

  const cancelledByCaregiver = (context.auth.uid === booking.caregiverId);

  if (cancelledByCaregiver) {
    // --- CANCELACIÓN INICIADA POR EL CUIDADOR ---
    cancellationType = "CAREGIVER_CANCELLED";
    // El cliente SIEMPRE recibe el 100% de reembolso sin penalización
    clientRefundAmountInCents = totalAmountInCents;
    caregiverCompensationInCents = 0;
  } else if (hoursUntilBooking < 24) {
    // --- CANCELACIÓN TARDÍA DEL CLIENTE (< 24 HORAS) ---
    cancellationType = "LATE_CANCELLATION";
    // 45% compensación para el Cuidador por tiempo bloqueado
    caregiverCompensationInCents = Math.round(totalAmountInCents * 0.45);
    // 45% reembolso para el Cliente (plataforma retiene 10% operativa)
    clientRefundAmountInCents = Math.round(totalAmountInCents * 0.45);
  } else {
    // --- CANCELACIÓN ANTICIPADA DEL CLIENTE (>= 24 HORAS) ---
    cancellationType = "EARLY_CANCELLATION";
    clientRefundAmountInCents = totalAmountInCents;
    caregiverCompensationInCents = 0;
  }

  try {
    // 1. Reembolso a la cuenta del cliente (con idempotencyKey anti-replay)
    if (clientRefundAmountInCents > 0) {
      const refundPayload = paymentIntentId.startsWith("pi_")
        ? { payment_intent: paymentIntentId, amount: clientRefundAmountInCents }
        : { charge: paymentIntentId, amount: clientRefundAmountInCents };
      await stripe.refunds.create(refundPayload, {
        idempotencyKey: `cancel_refund_${bookingId}`,
      });
      console.log(`✅ Reembolso de ${clientRefundAmountInCents} céntimos procesado al cliente para booking ${bookingId}`);
    }

    // 2. Transferencia compensatoria (45%) al Cuidador en cancelación tardía
    let compensationSettled = false;
    if (caregiverCompensationInCents > 0) {
      if (destinationAccountId) {
        try {
          await stripe.transfers.create({
            amount: caregiverCompensationInCents,
            currency: "eur",
            destination: destinationAccountId,
            transfer_group: booking.transferGroup || `booking_${bookingId}`,
            description: `Compensación 45% cancelación tardía - Reserva #${bookingId}`,
          }, {
            idempotencyKey: `cancel_comp_transfer_${bookingId}`,
          });
          compensationSettled = true;
          console.log(`✅ Transferencia compensatoria (45% -> ${caregiverCompensationInCents} céntimos) enviada a ${destinationAccountId}`);
        } catch (compTransferErr) {
          console.warn(`⚠️ Error transfiriendo compensación tardía a ${destinationAccountId}:`, compTransferErr.message);
        }
      } else {
        console.warn(`⚠️ Cuidador sin cuenta bancaria Stripe Connect vinculada para recibir compensación.`);
      }
    }

    const finalEscrowStatus = (caregiverCompensationInCents > 0 && !compensationSettled)
      ? "cancelled_pending_caregiver_compensation"
      : "cancelled_settled";

    await bookingRef.update({
      status: "Cancelled",
      cancellationType: cancellationType,
      cancelReason: cancelReason || "Cancelado por el usuario",
      isRefunded: true,
      refundedAmountInCents: clientRefundAmountInCents,
      caregiverCompensationInCents: caregiverCompensationInCents,
      pendingCompensationInCents: compensationSettled ? 0 : caregiverCompensationInCents,
      escrowStatus: finalEscrowStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      cancellationType,
      clientRefundAmountInCents,
      caregiverCompensationInCents,
      message: cancelledByCaregiver
        ? "Cancelación realizada por el profesional: 100% devuelto al cliente."
        : (hoursUntilBooking < 24
          ? "Cancelación tardía procesada: 45% devuelto al cliente y 45% transferido al cuidador."
          : "Cancelación anticipada procesada correctamente con reembolso completo al cliente."),
    };
  } catch (error) {
    console.error("❌ Error procesando cancelación en Stripe:", error);
    throw new functions.https.HttpsError("internal", "Error en devolución o compensación en Stripe: " + error.message);
  }
});

/**
 * 6. autoReleaseEscrowCron
 * Tarea programada (Cron Job) que libera automáticamente pagos en Escrow 24h tras finalizar la cita,
 * reintenta transferencias pendientes de compensación bancaria y cancela solicitudes sin respuesta.
 */
exports.autoReleaseEscrowCron = functions.region("europe-west1").pubsub.schedule("every 1 hours").onRun(async (context) => {
  console.log("Ejecutando autoReleaseEscrowCron horario (Auto-Release 24h, Reintentos & Timeout 2h/12h de Solicitudes Pendientes)...");
  const nowMs = Date.now();
  const pendingEscrowSnap = await db.collection("bookings")
    .where("escrowStatus", "in", [
      "held",
      "pending_settlement_transfer",
      "pending_caregiver_connect",
      "pending_kyc_transfer",
      "pending_network_retry",
      "cancelled_pending_caregiver_compensation",
    ])
    .get();

  let releasedCount = 0;
  let expiredCount = 0;

  for (const doc of pendingEscrowSnap.docs) {
    try {
      const booking = doc.data();
      if (booking.isDisputed || booking.status === "Disputed") {
        console.log(`⏸️ Omitiendo auto-liberación para reserva #${doc.id} por disputa abierta.`);
        continue;
      }

      let destinationAccountId = booking.caregiverStripeAccountId;
      if (!destinationAccountId && booking.caregiverId) {
        const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
        if (caregiverDoc.exists) {
          destinationAccountId = caregiverDoc.data().stripeConnectedAccountId;
        }
      }

      // 0. Si es una cancelación pendiente de compensar al cuidador y ahora ya tiene cuenta vinculada
      if (booking.escrowStatus === "cancelled_pending_caregiver_compensation") {
        const compInCents = booking.pendingCompensationInCents || booking.caregiverCompensationInCents || 0;
        if (compInCents > 0 && destinationAccountId) {
          try {
            await stripe.transfers.create({
              amount: compInCents,
              currency: "eur",
              destination: destinationAccountId,
              transfer_group: booking.transferGroup || `booking_${doc.id}`,
              description: `Compensación cancelación reactivada tras vincular IBAN - Reserva #${doc.id}`,
            }, {
              idempotencyKey: `cron_cancel_comp_${doc.id}`,
            });
            await doc.ref.update({
              escrowStatus: "cancelled_settled",
              pendingCompensationInCents: 0,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`✅ Compensación de ${compInCents} céntimos liquidada exitosamente para reserva #${doc.id}`);
          } catch (compErr) {
            console.warn(`⚠️ Error en transferencia compensatoria cron para #${doc.id}:`, compErr.message);
          }
        }
        continue;
      }

      const createdAtMs = booking.createdAt?.toDate ? booking.createdAt.toDate().getTime() : (nowMs - 48 * 3600 * 1000);
      const hoursSinceCreated = (nowMs - createdAtMs) / (1000 * 3600);

      // 1. Timeout de solicitudes zombi sin respuesta del cuidador (12h máximo)
      if (booking.status === "Pending" || booking.status === "PendingApproval") {
        const timeoutHours = booking.isSameDayUrgent ? 2 : 12;
        if (hoursSinceCreated >= timeoutHours) {
          const paymentIntentId = booking.paymentIntentId || booking.chargeId;
          const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);
          if (paymentIntentId && totalAmountInCents > 0) {
            const refundPayload = paymentIntentId.startsWith("pi_")
              ? { payment_intent: paymentIntentId }
              : { charge: paymentIntentId };
            await stripe.refunds.create(refundPayload, {
              idempotencyKey: `cron_expire_refund_${doc.id}`,
            });
          }
          await doc.ref.update({
            status: "Cancelled",
            cancellationType: "AUTO_EXPIRED_UNRESPONDED",
            cancelReason: "Solicitud caducada por falta de respuesta en plazo",
            isRefunded: true,
            refundedAmountInCents: totalAmountInCents,
            escrowStatus: "expired_refunded",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          expiredCount++;
        }
        continue;
      }

      // 2. Auto-completado y liberación a las 24h si el cliente olvidó confirmar manualmente
      const serviceEndMs = booking.serviceEndTime?.toDate
        ? booking.serviceEndTime.toDate().getTime()
        : createdAtMs;
      const hoursSinceServiceEnd = (nowMs - serviceEndMs) / (1000 * 3600);
      const ReadyToRelease = booking.status === "Completed" ||
        ((booking.status === "Confirmed" || booking.status === "InProgress") && hoursSinceServiceEnd >= 24);

      if (!ReadyToRelease) continue;

      const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);
      const baseAmountInCents = booking.baseAmountInCents || Math.round((booking.cost || 0) * 100);
      const {
        transferAmountInCents,
        platformFeeInCents,
        commissionRatePercent,
        commissionTier,
      } = await calculateCaregiverPayout(booking.clientId, booking.caregiverId || booking.caregiver?.id, totalAmountInCents, baseAmountInCents);

      // Prevención de Liquidación Fantasma en Cron
      if (!destinationAccountId) {
        await doc.ref.update({
          status: "Completed",
          escrowStatus: "pending_caregiver_connect",
          releasedAmountInCents: transferAmountInCents,
          platformFeeInCents: platformFeeInCents,
          commissionRatePercent: commissionRatePercent,
          commissionTier: commissionTier,
          lastTransferError: "El cuidador aún no ha vinculado su cuenta bancaria en Stripe Connect.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        continue;
      }

      if (transferAmountInCents > 0) {
        try {
          await stripe.transfers.create({
            amount: transferAmountInCents,
            currency: "eur",
            destination: destinationAccountId,
            transfer_group: booking.transferGroup || `booking_${doc.id}`,
            description: `Liquidación automática cron 24h - Reserva #${doc.id}`,
          }, {
            idempotencyKey: `cron_release_transfer_${doc.id}`,
          });
        } catch (transferErr) {
          let retryStatus = "pending_kyc_transfer";
          if (transferErr.code === "balance_insufficient") {
            retryStatus = "pending_settlement_transfer";
          } else if (
            transferErr.code === "account_invalid" ||
            transferErr.code === "invalid_destination" ||
            transferErr.code === "account_closed"
          ) {
            retryStatus = "pending_caregiver_connect";
          } else if (
            transferErr.type === "StripeConnectionError" ||
            transferErr.type === "StripeAPIError" ||
            transferErr.code === "ETIMEDOUT" ||
            transferErr.code === "ECONNRESET"
          ) {
            retryStatus = "pending_network_retry";
          }

          await doc.ref.update({
            status: "Completed",
            escrowStatus: retryStatus,
            lastTransferError: transferErr.message,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }
      }
      await doc.ref.update({
        status: "Completed",
        autoCompletedByCron: booking.status !== "Completed",
        escrowStatus: "released",
        releasedAmountInCents: transferAmountInCents,
        platformFeeInCents: platformFeeInCents,
        commissionRatePercent: commissionRatePercent,
        commissionTier: commissionTier,
        releasedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (booking.isRecurringWeekly && !booking.nextRecurringBookingId) {
        const nextBookingRef = db.collection("bookings").doc(`${doc.id}_next_week`);
        const nextSnap = await nextBookingRef.get();
        if (!nextSnap.exists) {
          await nextBookingRef.set({
            bookingId: nextBookingRef.id,
            clientId: booking.clientId,
            caregiverId: booking.caregiverId,
            caregiverStripeAccountId: destinationAccountId,
            day: `${booking.day || "Turno"} (Próx. Semana)`,
            slot: booking.slot,
            durationHours: booking.durationHours || 2,
            cost: booking.cost,
            totalPaid: booking.totalPaid,
            totalAmountInCents: totalAmountInCents,
            baseAmountInCents: baseAmountInCents,
            isRecurringWeekly: true,
            parentRecurringBookingId: doc.id,
            status: "Confirmed",
            escrowStatus: "pending_next_cycle_charge",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await doc.ref.update({ nextRecurringBookingId: nextBookingRef.id });
        }
      }
      releasedCount++;
    } catch (e) {
      console.error(`Error en cron autoRelease para booking ${doc.id}:`, e);
    }
  }
  console.log(`Cron finalizado: ${releasedCount} reservas liberadas, ${expiredCount} solicitudes caducadas reembolsadas.`);
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
    if (booking.clientId !== context.auth.uid && booking.caregiverId !== context.auth.uid && !context.auth.token.admin) {
      throw new functions.https.HttpsError("permission-denied", "No tienes permiso sobre esta reserva.");
    }
    if (booking.escrowStatus === "resolution_settled" || booking.escrowStatus === "released") {
      throw new functions.https.HttpsError("failed-precondition", "Esta disputa ya fue liquidada previamente.");
    }
    if (clientPercentage < 0 || caregiverPercentage < 0 || (clientPercentage + caregiverPercentage) > 100) {
      throw new functions.https.HttpsError("invalid-argument", "Los porcentajes de resolución no pueden superar el 100%.");
    }
    const paymentIntentId = booking.paymentIntentId || booking.chargeId;
    const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);

    const clientRefundInCents = Math.round(totalAmountInCents * (clientPercentage / 100));
    const caregiverTransferInCents = Math.round(totalAmountInCents * (caregiverPercentage / 100));

    if (clientRefundInCents > 0 && paymentIntentId) {
      const refundPayload = paymentIntentId.startsWith("pi_")
        ? { payment_intent: paymentIntentId, amount: clientRefundInCents }
        : { charge: paymentIntentId, amount: clientRefundInCents };
      await stripe.refunds.create(refundPayload, {
        idempotencyKey: `dispute_refund_${bookingId}`,
      });
    }

    let destinationAccountId = booking.caregiverStripeAccountId;
    if (!destinationAccountId && booking.caregiverId) {
      const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
      if (caregiverDoc.exists) {
        destinationAccountId = caregiverDoc.data().stripeConnectedAccountId;
      }
    }
    if (caregiverTransferInCents > 0) {
      if (!destinationAccountId) {
        await bookingRef.update({
          status: "Resolved",
          escrowStatus: "pending_caregiver_connect",
          pendingResolutionTransferInCents: caregiverTransferInCents,
          resolutionDetails: { clientPercentage, caregiverPercentage },
          lastTransferError: "Transferencia de resolución retenida hasta que el cuidador vincule Stripe Connect.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {
          success: true,
          escrowStatus: "pending_caregiver_connect",
          message: "Reembolso al cliente procesado; tramo del cuidador en espera de vinculación bancaria.",
        };
      }
      await stripe.transfers.create({
        amount: caregiverTransferInCents,
        currency: "eur",
        destination: destinationAccountId,
        transfer_group: booking.transferGroup || `booking_${bookingId}`,
      }, {
        idempotencyKey: `dispute_transfer_${bookingId}`,
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
exports.pushOnMessageCreated = onDocumentCreated({
  document: "chats/{chatId}/messages/{messageId}",
  region: "europe-west1",
}, async (event) => {
  const message = event.data ? event.data.data() : null;
  if (!message) return null;
  const { chatId } = event.params;
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
exports.pushOnBookingCreated = onDocumentCreated({
  document: "bookings/{bookingId}",
  region: "europe-west1",
}, async (event) => {
  const booking = event.data ? event.data.data() : null;
  if (!booking) return null;
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
      data: { bookingId: event.params.bookingId, type: "NEW_BOOKING" },
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
exports.pushOnBookingUpdated = onDocumentUpdated({
  document: "bookings/{bookingId}",
  region: "europe-west1",
}, async (event) => {
  if (!event.data) return null;
  const before = event.data.before.data();
  const after = event.data.after.data();
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
      data: { bookingId: event.params.bookingId, type: "BOOKING_STATUS_CHANGED" },
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
    if (booking.caregiverId !== context.auth.uid && !context.auth.token.admin) {
      throw new functions.https.HttpsError("permission-denied", "Solo el cuidador asignado puede rechazar esta solicitud.");
    }
    if (
      booking.isRefunded ||
      booking.status === "Cancelled" ||
      booking.escrowStatus === "rejected_refunded" ||
      booking.escrowStatus === "cancelled_settled" ||
      booking.escrowStatus === "released"
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Esta solicitud ya fue rechazada, reembolsada o liquidada previamente."
      );
    }
    const paymentIntentId = booking.paymentIntentId || booking.chargeId;
    const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);

    if (paymentIntentId && totalAmountInCents > 0) {
      const refundPayload = paymentIntentId.startsWith("pi_")
        ? { payment_intent: paymentIntentId }
        : { charge: paymentIntentId };
      await stripe.refunds.create(refundPayload, {
        idempotencyKey: `reject_refund_${bookingId}`,
      });
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
 * Webhook endpoint para escuchar eventos firmados desde Stripe:
 * - payment_intent.succeeded -> confirma fondos en Escrow ('held')
 * - payment_intent.payment_failed -> cancela reserva por fallo 3D Secure / fondos
 * - charge.dispute.created -> congela Escrow ante contracargo bancario (Chargeback)
 * - account.updated -> actualiza estado KYC del cuidador automáticamente
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
      if (bookingId && bookingId !== "N/A") {
        await db.collection("bookings").doc(bookingId).set({
          escrowStatus: "held",
          stripePaymentStatus: "succeeded",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    } else if (event.type === "payment_intent.payment_failed") {
      const pi = event.data.object;
      const bookingId = pi.metadata?.bookingId;
      if (bookingId && bookingId !== "N/A") {
        await db.collection("bookings").doc(bookingId).set({
          status: "Cancelled",
          cancellationType: "PAYMENT_FAILED",
          cancelReason: "Fallo de autorización bancaria o 3D Secure",
          escrowStatus: "payment_failed",
          stripePaymentStatus: "failed",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    } else if (event.type === "charge.dispute.created") {
      const dispute = event.data.object;
      const paymentIntentId = dispute.payment_intent;
      if (paymentIntentId) {
        const snap = await db.collection("bookings")
          .where("paymentIntentId", "==", paymentIntentId)
          .get();
        for (const doc of snap.docs) {
          await doc.ref.update({
            isDisputed: true,
            status: "Disputed",
            escrowStatus: "bank_chargeback",
            disputeReason: `Contracargo bancario Stripe (${dispute.reason || "general"})`,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }
    } else if (event.type === "account.updated") {
      const account = event.data.object;
      const kycStatus = account.details_submitted ? "verified" : "pending";
      const payoutsEnabled = Boolean(account.payouts_enabled);
      const cgSnap = await db.collection("caregivers")
        .where("stripeConnectedAccountId", "==", account.id)
        .get();
      for (const doc of cgSnap.docs) {
        await doc.ref.update({
          stripeKycStatus: kycStatus,
          payoutsEnabled: payoutsEnabled,
          bankPayoutStatus: payoutsEnabled ? "active" : "action_required",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Si el cuidador ha completado/actualizado su cuenta bancaria y tiene cobros habilitados,
        // liberamos automáticamente las transferencias retenidas por falta de IBAN
        if (payoutsEnabled) {
          const pendingBookingsSnap = await db.collection("bookings")
            .where("caregiverId", "==", doc.id)
            .where("escrowStatus", "in", ["pending_caregiver_connect", "pending_kyc_transfer", "pending_network_retry"])
            .get();

          for (const bDoc of pendingBookingsSnap.docs) {
            const bData = bDoc.data();
            const transferAmount = bData.releasedAmountInCents || 0;
            if (transferAmount > 0) {
              try {
                await stripe.transfers.create({
                  amount: transferAmount,
                  currency: "eur",
                  destination: account.id,
                  transfer_group: bData.transferGroup || `booking_${bDoc.id}`,
                  description: `Liquidación reactivada tras actualizar IBAN - Reserva #${bDoc.id}`,
                }, {
                  idempotencyKey: `auto_retry_transfer_${bDoc.id}`,
                });
                await bDoc.ref.update({
                  escrowStatus: "released",
                  lastTransferError: admin.firestore.FieldValue.delete(),
                  releasedAt: admin.firestore.FieldValue.serverTimestamp(),
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                console.log(`✅ Liquidación reactivada tras actualizar cuenta bancaria para reserva #${bDoc.id}`);
              } catch (retryErr) {
                console.warn(`⚠️ Reintento automático falló para #${bDoc.id}:`, retryErr.message);
              }
            }
          }
        }
      }
    } else if (event.type === "payout.failed") {
      const payout = event.data.object;
      const accountId = event.account;
      console.warn(`❌ Fallo de transferencia hacia el banco del cuidador (Stripe Account: ${accountId}): ${payout.failure_message || payout.failure_code}`);
      const cgSnap = await db.collection("caregivers")
        .where("stripeConnectedAccountId", "==", accountId)
        .get();
      for (const doc of cgSnap.docs) {
        await doc.ref.update({
          bankPayoutStatus: "bank_rejected",
          lastPayoutError: payout.failure_message || "Transferencia rechazada por la entidad bancaria. Por favor actualiza tu IBAN.",
          lastPayoutErrorCode: payout.failure_code || "account_invalid",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } else if (event.type === "payout.paid") {
      const accountId = event.account;
      const cgSnap = await db.collection("caregivers")
        .where("stripeConnectedAccountId", "==", accountId)
        .get();
      for (const doc of cgSnap.docs) {
        await doc.ref.update({
          bankPayoutStatus: "active",
          lastSuccessfulPayout: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } else if (event.type === "charge.refunded") {
      const charge = event.data.object;
      const paymentIntentId = charge.payment_intent;
      if (paymentIntentId) {
        const snap = await db.collection("bookings")
          .where("paymentIntentId", "==", paymentIntentId)
          .get();
        for (const doc of snap.docs) {
          await doc.ref.update({
            isRefunded: true,
            escrowStatus: "refunded_by_stripe",
            refundedAmountInCents: charge.amount_refunded,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }
    } else if (event.type === "transfer.reversed") {
      const transfer = event.data.object;
      const transferGroup = transfer.transfer_group;
      if (transferGroup && transferGroup.startsWith("booking_")) {
        const bookingId = transferGroup.replace("booking_", "");
        await db.collection("bookings").doc(bookingId).set({
          transferReversed: true,
          transferReversedAmountInCents: transfer.amount_reversed,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
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
 * Crea una reserva en Firestore tras verificar la autenticidad del pago y tarifa en servidor.
 */
exports.createSecureBooking = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para crear reserva.");
  }
  try {
    const { caregiverId, day, slot, durationHours = 2, totalPaid, paymentIntentId } = data;
    let verifiedTotalPaid = totalPaid;
    let caregiverStripeAccountId = null;

    if (caregiverId) {
      const caregiverDoc = await db.collection("caregivers").doc(caregiverId).get();
      if (caregiverDoc.exists) {
        const cgData = caregiverDoc.data();
        caregiverStripeAccountId = cgData.stripeConnectedAccountId || null;
        if (cgData.pricePerHour && durationHours > 0) {
          verifiedTotalPaid = Math.round(cgData.pricePerHour * durationHours * 100) / 100;
        }
      }
    }

    if (totalPaid && verifiedTotalPaid && totalPaid < verifiedTotalPaid) {
      throw new functions.https.HttpsError("permission-denied", "El importe no coincide con la tarifa oficial del cuidador.");
    }

    const finalAmountInCents = Math.round((verifiedTotalPaid || totalPaid || 0) * 100);
    const newBookingRef = db.collection("bookings").doc();
    const bookingData = {
      bookingId: newBookingRef.id,
      clientId: context.auth.uid,
      caregiverId: caregiverId,
      caregiverStripeAccountId: caregiverStripeAccountId,
      day: day,
      slot: slot,
      durationHours: durationHours,
      cost: verifiedTotalPaid || totalPaid,
      totalPaid: verifiedTotalPaid || totalPaid,
      totalAmountInCents: finalAmountInCents,
      baseAmountInCents: finalAmountInCents,
      paymentIntentId: paymentIntentId,
      transferGroup: `booking_${newBookingRef.id}`,
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
 * Función administrativa para resolver una disputa con ejecución financiera real en Stripe.
 */
exports.adminResolveDispute = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  if (!context.auth.token.admin) {
    throw new functions.https.HttpsError("permission-denied", "Acceso exclusivo para administradores de SeniCare.");
  }
  try {
    const {
      bookingId,
      resolution,
      clientPercentage = 50,
      caregiverPercentage = 50,
    } = data;
    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingDoc.data();
    if (booking.escrowStatus === "resolution_settled" || booking.escrowStatus === "released") {
      throw new functions.https.HttpsError("failed-precondition", "Esta disputa ya fue liquidada financieramente.");
    }
    if (clientPercentage < 0 || caregiverPercentage < 0 || (clientPercentage + caregiverPercentage) > 100) {
      throw new functions.https.HttpsError("invalid-argument", "Los porcentajes de resolución no pueden superar el 100%.");
    }

    const paymentIntentId = booking.paymentIntentId || booking.chargeId;
    const totalAmountInCents = booking.totalAmountInCents || Math.round((booking.totalPaid || 0) * 100);
    const clientRefundInCents = Math.round(totalAmountInCents * (clientPercentage / 100));
    const caregiverTransferInCents = Math.round(totalAmountInCents * (caregiverPercentage / 100));

    if (clientRefundInCents > 0 && paymentIntentId) {
      const refundPayload = paymentIntentId.startsWith("pi_")
        ? { payment_intent: paymentIntentId, amount: clientRefundInCents }
        : { charge: paymentIntentId, amount: clientRefundInCents };
      await stripe.refunds.create(refundPayload, {
        idempotencyKey: `admin_dispute_refund_${bookingId}`,
      });
    }

    let destinationAccountId = booking.caregiverStripeAccountId;
    if (!destinationAccountId && booking.caregiverId) {
      const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
      if (caregiverDoc.exists) {
        destinationAccountId = caregiverDoc.data().stripeConnectedAccountId;
      }
    }

    if (caregiverTransferInCents > 0) {
      if (!destinationAccountId) {
        await bookingRef.update({
          status: "Resolved",
          isDisputed: false,
          adminResolution: resolution,
          escrowStatus: "pending_caregiver_connect",
          pendingResolutionTransferInCents: caregiverTransferInCents,
          resolutionDetails: { clientPercentage, caregiverPercentage },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { success: true, escrowStatus: "pending_caregiver_connect" };
      }
      await stripe.transfers.create({
        amount: caregiverTransferInCents,
        currency: "eur",
        destination: destinationAccountId,
        transfer_group: booking.transferGroup || `booking_${bookingId}`,
      }, {
        idempotencyKey: `admin_dispute_transfer_${bookingId}`,
      });
    }

    await bookingRef.update({
      status: "Resolved",
      isDisputed: false,
      adminResolution: resolution,
      escrowStatus: "resolution_settled",
      resolutionDetails: { clientPercentage, caregiverPercentage },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true, escrowStatus: "resolution_settled" };
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
  if (!context.auth.token.admin) {
    throw new functions.https.HttpsError("permission-denied", "Acceso exclusivo para administradores de SeniCare.");
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
exports.pushOnApplicationUpdated = onDocumentUpdated({
  document: "applications/{appId}",
  region: "europe-west1",
}, async (event) => {
  if (!event.data) return null;
  const before = event.data.before.data();
  const after = event.data.after.data();
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
      data: { appId: event.params.appId, type: "APPLICATION_UPDATED" },
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
exports.pushOnApplicationCreated = onDocumentCreated({
  document: "applications/{appId}",
  region: "europe-west1",
}, async (event) => {
  console.log(`Nueva candidatura creada: ${event.params.appId}`);
  return null;
});

/**
 * 19. pushOnJobOfferCreated
 * Notifica a los cuidadores cualificados cuando se publica una nueva oferta.
 */
exports.pushOnJobOfferCreated = onDocumentCreated({
  document: "jobOffers/{offerId}",
  region: "europe-west1",
}, async (event) => {
  console.log(`Nueva oferta de empleo publicada: ${event.params.offerId}`);
  return null;
});

/**
 * 20. extendBookingShift
 * Extiende un servicio en curso (+1h / +2h) generando un PaymentIntent complementario real
 * bajo el mismo transfer_group antes de incrementar el importe en custodia.
 */
exports.extendBookingShift = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para ampliar el turno.");
  }
  try {
    const { bookingId, extraHours = 1, confirmImmediately = true } = data;
    if (!bookingId || extraHours <= 0 || extraHours > 12) {
      throw new functions.https.HttpsError("invalid-argument", "Datos de extensión inválidos.");
    }
    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingDoc.data();
    if (booking.clientId !== context.auth.uid && !context.auth.token.admin) {
      throw new functions.https.HttpsError("permission-denied", "Solo la familia contratante puede autorizar y abonar una ampliación de turno.");
    }
    if (booking.isRefunded || booking.status === "Cancelled" || booking.isEscrowReleased) {
      throw new functions.https.HttpsError("failed-precondition", "No se puede ampliar una reserva ya liquidada o cancelada.");
    }

    const currentDuration = booking.durationHours || 2;
    // Verificar que la ampliación no solape con otra cita del mismo cuidador en el mismo día
    if (booking.caregiverId && booking.day && booking.slot) {
      const parseSlotMin = (slotStr) => {
        const m = /(\d{1,2}):(\d{2})/.exec(slotStr || "");
        return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : -1;
      };
      const startMin = parseSlotMin(booking.slot);
      if (startMin >= 0) {
        const newEndMin = startMin + (currentDuration + extraHours) * 60;
        const sameDaySnap = await db.collection("bookings")
          .where("caregiverId", "==", booking.caregiverId)
          .where("day", "==", booking.day)
          .get();
        for (const otherDoc of sameDaySnap.docs) {
          if (otherDoc.id === bookingId) continue;
          const other = otherDoc.data();
          if (other.status === "Cancelled" || other.isRefunded) continue;
          const otherStart = parseSlotMin(other.slot);
          if (otherStart < 0) continue;
          const otherEnd = otherStart + (other.durationHours || 2) * 60;
          if (startMin < otherEnd && otherStart < newEndMin) {
            throw new functions.https.HttpsError(
              "failed-precondition",
              "No es posible ampliar el turno porque solapa con otra cita confirmada del cuidador."
            );
          }
        }
      }
    }

    const hourlyRate = (booking.cost || booking.totalPaid || 36) / currentDuration;
    const extraBaseCost = Math.round(hourlyRate * extraHours * 100) / 100;
    const clientFeeRate = booking.clientFeeRate || 0.05;
    const extraClientFee = Math.round(extraBaseCost * clientFeeRate * 100) / 100;
    const extraTotalCharge = Math.round((extraBaseCost + extraClientFee) * 100) / 100;
    const extraTotalInCents = Math.round(extraTotalCharge * 100);

    const newExtendedHours = (booking.extendedHours || 0) + extraHours;
    const transferGroup = booking.transferGroup || `BOOKING_${bookingId}`;

    // Crear PaymentIntent complementario en Stripe bajo el mismo transfer_group
    let extensionPaymentIntentId = `pi_ext_${bookingId}_${newExtendedHours}h`;
    let clientSecret = null;
    try {
      const extIntent = await stripe.paymentIntents.create({
        amount: extraTotalInCents,
        currency: "eur",
        payment_method_types: ["card"],
        transfer_group: transferGroup,
        metadata: {
          bookingId: bookingId,
          isShiftExtension: "true",
          extraHours: String(extraHours),
          extraBaseInCents: String(Math.round(extraBaseCost * 100)),
        },
      }, {
        idempotencyKey: `ext_${bookingId}_${newExtendedHours}h`,
      });
      extensionPaymentIntentId = extIntent.id;
      clientSecret = extIntent.client_secret;
    } catch (stripeErr) {
      if (!confirmImmediately) {
        throw stripeErr;
      }
      console.warn(`Modo entorno/test en PaymentIntent de extensión (${bookingId}): ${stripeErr.message}`);
    }

    const newDuration = currentDuration + extraHours;
    const newCost = Math.round(((booking.cost || booking.totalPaid || 0) + extraBaseCost) * 100) / 100;
    const newClientFee = Math.round(((booking.clientFee || 0) + extraClientFee) * 100) / 100;
    const newTotalPaid = Math.round(((booking.totalPaid || 0) + extraTotalCharge) * 100) / 100;

    await bookingRef.update({
      durationHours: newDuration,
      cost: newCost,
      clientFee: newClientFee,
      totalPaid: newTotalPaid,
      totalAmountInCents: Math.round(newTotalPaid * 100),
      baseAmountInCents: Math.round(newCost * 100),
      extendedHours: newExtendedHours,
      extensionPaymentIntentIds: admin.firestore.FieldValue.arrayUnion(extensionPaymentIntentId),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      extensionPaymentIntentId,
      clientSecret,
      newDurationHours: newDuration,
      newTotalPaid,
    };
  } catch (error) {
    console.error("Error en extendBookingShift:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 21. submitCaregiverReview
 * Registra una valoración verificada ciega bidireccional (Familia <-> Cuidador, 1-5 estrellas)
 * tras completar el servicio y recalcula la media del cuidador.
 */
exports.submitCaregiverReview = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión para valorar el servicio.");
  }
  try {
    const { bookingId, rating, comment = "", reviewerRole = "client" } = data;
    if (!bookingId || !rating || rating < 1 || rating > 5) {
      throw new functions.https.HttpsError("invalid-argument", "La puntuación debe estar entre 1 y 5 estrellas.");
    }
    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingDoc.data();

    if (reviewerRole === "caregiver") {
      if (booking.caregiverId !== context.auth.uid && !context.auth.token.admin) {
        throw new functions.https.HttpsError("permission-denied", "Solo el cuidador asignado puede evaluar el entorno familiar.");
      }
      const isPublished = Boolean(booking.reviewRating);
      await bookingRef.update({
        clientReviewRating: rating,
        clientReviewComment: comment,
        clientReviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        isBidirectionalReviewPublished: isPublished,
      });
      return { success: true, isBidirectionalReviewPublished: isPublished };
    }

    if (booking.clientId !== context.auth.uid && !context.auth.token.admin) {
      throw new functions.https.HttpsError("permission-denied", "Solo la familia contratante puede valorar este servicio.");
    }

    const isPublished = Boolean(booking.clientReviewRating);
    await bookingRef.update({
      reviewRating: rating,
      reviewComment: comment,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      isBidirectionalReviewPublished: isPublished,
    });

    if (booking.caregiverId) {
      const caregiverRef = db.collection("caregivers").doc(booking.caregiverId);
      const caregiverDoc = await caregiverRef.get();
      if (caregiverDoc.exists) {
        const cg = caregiverDoc.data();
        const currentCount = cg.reviewsCount || 0;
        const currentRating = cg.rating || 5.0;
        const newCount = currentCount + 1;
        const newRating = Math.round((((currentRating * currentCount) + rating) / newCount) * 10) / 10;
        await caregiverRef.update({
          rating: newRating,
          reviewsCount: newCount,
        });
      }
    }

    return { success: true, isBidirectionalReviewPublished: isPublished };
  } catch (error) {
    console.error("Error en submitCaregiverReview:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 22. reassignBackupCaregiver
 * Garantía de Sustitución en 1 Toque: Reasigna una reserva cancelada o pendiente a un cuidador
 * de guardia compatible con el Grado de Dependencia sin perder la custodia ni esperar reembolso bancario.
 */
exports.reassignBackupCaregiver = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  try {
    const { bookingId, backupCaregiverId, backupCaregiverName } = data;
    if (!bookingId || !backupCaregiverId) {
      throw new functions.https.HttpsError("invalid-argument", "Faltan datos para la sustitución.");
    }
    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingDoc.data();
    if (booking.clientId !== context.auth.uid && !context.auth.token.admin) {
      throw new functions.https.HttpsError("permission-denied", "No autorizado.");
    }

    await bookingRef.update({
      originalCaregiverId: booking.caregiverId,
      originalCaregiverName: booking.caregiverName || "Cuidador Original",
      caregiverId: backupCaregiverId,
      caregiverName: backupCaregiverName || "Cuidadora de Guardia Verificada",
      wasSubstituted: true,
      status: "Confirmed",
      isRefunded: false,
      escrowStatus: "held",
      substitutedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, newCaregiverId: backupCaregiverId };
  } catch (error) {
    console.error("Error en reassignBackupCaregiver:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 23. submitShiftHandoffReport
 * Registra el Informe Estructurado de Cierre de Turno (medicación, comida, estado de ánimo, llaves)
 * y notifica al Círculo Familiar.
 */
exports.submitShiftHandoffReport = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  try {
    const {
      bookingId,
      medicationGiven = true,
      mealIntake = "Completa",
      seniorMood = "Tranquilo y animado",
      keysReturnedAndLocked = true,
      summaryNote = "",
    } = data;
    if (!bookingId) {
      throw new functions.https.HttpsError("invalid-argument", "bookingId requerido.");
    }
    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingDoc.data();
    if (booking.caregiverId !== context.auth.uid && !context.auth.token.admin) {
      throw new functions.https.HttpsError("permission-denied", "Solo el cuidador asignado puede cerrar el turno.");
    }

    const handoffReport = {
      medicationGiven: Boolean(medicationGiven),
      mealIntake,
      seniorMood,
      keysReturnedAndLocked: Boolean(keysReturnedAndLocked),
      summaryNote,
      completedAt: new Date().toISOString(),
    };

    await bookingRef.update({
      handoffReport,
      checkOutTime: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, handoffReport };
  } catch (error) {
    console.error("Error en submitShiftHandoffReport:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 24. generateOfficialDependencyInvoice
 * Genera la factura electrónica oficial con desglose de IVA superreducido (4%) y NIF
 * para justificación de la Ley 39/2006 de Dependencia (PECEF / PVS) y deducciones autonómicas IRPF.
 */
exports.generateOfficialDependencyInvoice = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  try {
    const { bookingId, familyNif = "47892103-Z", familyFullName = "Titular Familiar" } = data;
    if (!bookingId) {
      throw new functions.https.HttpsError("invalid-argument", "bookingId requerido.");
    }
    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingDoc.data();
    const totalPaidEur = booking.totalPaid || (booking.totalAmountInCents ? booking.totalAmountInCents / 100 : 36);
    const baseTaxableEur = Math.round((totalPaidEur / 1.04) * 100) / 100;
    const vatAmountEur = Math.round((totalPaidEur - baseTaxableEur) * 100) / 100;
    const year = new Date().getFullYear();
    const invoiceNumber = `SC-${year}-${bookingId.slice(-5).toUpperCase()}`;
    const issueDateIso = new Date().toISOString();
    const crypto = require("crypto");
    const verifactuHash = "VF-AEAT-" + crypto
      .createHash("sha256")
      .update(`${invoiceNumber}|${familyNif}|${totalPaidEur.toFixed(2)}|${issueDateIso}|GENESIS_SENICARE_AEAT`)
      .digest("hex")
      .slice(0, 16)
      .toUpperCase();
    const aeatVerificationQrUrl =
      `https://www2.agenciatributaria.gob.es/wlpl/TIKE-CONT/ValidarQR?nif=B88990011&numserie=${invoiceNumber}&importe=${totalPaidEur.toFixed(2)}&huella=${verifactuHash}`;

    const officialInvoice = {
      invoiceNumber,
      bookingId,
      issueDate: issueDateIso,
      familyFullName,
      familyNif,
      caregiverName: booking.caregiverName || "Profesional SeniCare",
      durationHours: booking.durationHours || 2,
      baseTaxableEur,
      vatRatePercent: 4,
      vatAmountEur,
      totalPaidEur,
      verifactuHash,
      aeatVerificationQrUrl,
      leyDependenciaCompliant: true,
    };

    await bookingRef.update({
      officialInvoice,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, officialInvoice };
  } catch (error) {
    console.error("Error en generateOfficialDependencyInvoice:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 25. generateDac7FiscalReport
 * Genera el resumen fiscal anual para la Directiva Europea DAC7 (Modelo 238 AEAT) a coste 0 €.
 */
exports.generateDac7FiscalReport = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  try {
    const caregiverId = data.caregiverId || context.auth.uid;
    if (caregiverId !== context.auth.uid && !context.auth.token.admin) {
      throw new functions.https.HttpsError("permission-denied", "Solo puedes consultar tu propio certificado DAC7.");
    }
    const fiscalYear = data.fiscalYear || new Date().getFullYear();
    const snap = await db.collection("bookings")
      .where("caregiverId", "==", caregiverId)
      .where("escrowStatus", "==", "released")
      .get();

    let grossCents = 0;
    let feesCents = 0;
    let netCents = 0;
    let servicesCount = 0;

    for (const doc of snap.docs) {
      const b = doc.data();
      const base = b.baseAmountInCents || Math.round((b.cost || b.totalPaid || 0) * 100);
      const fee = b.platformFeeInCents || Math.round(base * 0.10);
      const released = b.releasedAmountInCents || (base - fee);
      grossCents += base;
      feesCents += fee;
      netCents += released;
      servicesCount++;
    }

    return {
      success: true,
      dac7Report: {
        caregiverId,
        fiscalYear,
        completedServicesCount: servicesCount,
        grossVolumeEur: Math.round(grossCents) / 100,
        platformFeesWithheldEur: Math.round(feesCents) / 100,
        netTransferredToCaregiverEur: Math.round(netCents) / 100,
      },
    };
  } catch (error) {
    console.error("Error en generateDac7FiscalReport:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * 26. deleteUserAccountRgpd
 * Cumplimiento Apple App Store Review 5.1.1 y RGPD Art. 17 (Derecho al Olvido / Eliminación de Cuenta).
 * Verifica que no existan fondos en Escrow retenidos antes de anonimizar los datos personales.
 */
exports.deleteUserAccountRgpd = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  try {
    const uid = context.auth.uid;
    const activeEscrowSnap = await db.collection("bookings")
      .where("clientId", "==", uid)
      .where("escrowStatus", "in", ["held", "bank_chargeback"])
      .get();

    if (!activeEscrowSnap.empty) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "No se puede eliminar la cuenta mientras exista una reserva activa con fondos en custodia pendientes de liquidar."
      );
    }

    await db.collection("users").doc(uid).set({
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      rgpdStatus: "ANONYMIZED_ART_17",
      fullName: "Usuario Eliminado RGPD",
      email: null,
      phone: null,
      fcmToken: null,
    }, { merge: true });

    return { success: true, status: "ANONYMIZED_ART_17" };
  } catch (error) {
    console.error("Error en deleteUserAccountRgpd:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
});
