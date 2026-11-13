const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const crypto = require("crypto");
const { defineSecret } = require("firebase-functions/params");

const stripeSecret = defineSecret("STRIPE_SECRET_KEY");
const webhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
const MASTER_ADMIN_EMAIL = "maverick6576@gmail.com";
const STANDARD_CLIENT_FEE_RATE = 0.03;

admin.initializeApp();

async function isAdminCaller(context) {
  if (!context || !context.auth) return false;
  const email = (context.auth.token?.email || "").trim().toLowerCase();
  const verified = context.auth.token?.email_verified === true;
  if (!email || !verified) return false;
  if (email === MASTER_ADMIN_EMAIL) return true;
  const adminDoc = await admin.firestore().collection("admins").doc(email).get();
  if (adminDoc.exists) return true;
  const originalEmail = (context.auth.token?.email || "").trim();
  if (originalEmail !== email) {
    const exactDoc = await admin.firestore().collection("admins").doc(originalEmail).get();
    if (exactDoc.exists) return true;
  }
  return false;
}

async function mergeUserClaims(uid, patch) {
  if (!uid) return;
  try {
    const userRecord = await admin.auth().getUser(uid);
    const existing = userRecord.customClaims || {};
    const next = { ...existing, ...patch };
    Object.keys(next).forEach((k) => {
      if (next[k] === null || next[k] === undefined) delete next[k];
    });
    await admin.auth().setCustomUserClaims(uid, next);
  } catch (e) {
    console.warn(`Could not update custom claims for ${uid}:`, e.message);
  }
}

function decodeBase32(base32Str) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const cleaned = String(base32Str || "").toUpperCase().replace(/=+$/, "").replace(/[^A-Z2-7]/g, "");
  let bits = 0;
  let value = 0;
  const output = [];
  for (let i = 0; i < cleaned.length; i++) {
    const idx = alphabet.indexOf(cleaned[i]);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      output.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(output);
}

function generateTotpAt(secret, epochMs) {
  const key = decodeBase32(secret);
  const counter = Math.floor(epochMs / 30000);
  const counterBuf = Buffer.alloc(8);
  counterBuf.writeUInt32BE(Math.floor(counter / 0x100000000), 0);
  counterBuf.writeUInt32BE(counter >>> 0, 4);
  const hmac = crypto.createHmac("sha1", key).update(counterBuf).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const binCode =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);
  return String(binCode % 1000000).padStart(6, "0");
}

function verifyTotpCode(secret, code) {
  const normalized = String(code || "").trim();
  if (!/^\d{6}$/.test(normalized) || !secret) return false;
  const now = Date.now();
  return [-30000, 0, 30000].some((offset) => {
    const candidate = generateTotpAt(secret, now + offset);
    return crypto.timingSafeEqual(Buffer.from(candidate), Buffer.from(normalized));
  });
}

const MADRID_TZ = "Europe/Madrid";
const madridDateTimeFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: MADRID_TZ,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hour12: false,
});

function getMadridOffsetMs(utcMs) {
  const parts = {};
  for (const part of madridDateTimeFormatter.formatToParts(new Date(utcMs))) {
    if (part.type !== "literal") {
      parts[part.type] = part.value;
    }
  }
  const hour = parts.hour === "24" ? 0 : Number(parts.hour);
  const asUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    hour,
    Number(parts.minute),
    Number(parts.second)
  );
  return asUtc - utcMs;
}

function madridWallClockToUtcDate(y, m, d, hh, mm) {
  const approxUtc = Date.UTC(y, m - 1, d, hh, mm, 0);
  const offset1 = getMadridOffsetMs(approxUtc);
  let candidate = approxUtc - offset1;
  const offset2 = getMadridOffsetMs(candidate);
  if (offset2 !== offset1) {
    candidate = approxUtc - offset2;
  }
  return new Date(candidate);
}

function parseBookingYmd(dayStr) {
  if (!dayStr) return null;
  let dateParts;
  if (dayStr.includes("/")) {
    const parts = dayStr.split("/");
    dateParts = [parts[2], parts[1], parts[0]];
  } else {
    dateParts = dayStr.split("-");
  }
  if (!dateParts || dateParts.length !== 3) return null;
  const y = parseInt(dateParts[0], 10);
  const m = parseInt(dateParts[1], 10);
  const d = parseInt(dateParts[2], 10);
  if ([y, m, d].some((n) => isNaN(n))) return null;
  return { y, m, d };
}

function parseBookingStartDateTime(dayStr, slotStr) {
  if (!dayStr || !slotStr) return null;
  const ymd = parseBookingYmd(dayStr);
  if (!ymd) return null;
  const startStr = slotStr.includes("-") ? slotStr.split("-")[0].trim() : slotStr.trim();
  const timeParts = startStr.split(":");
  const hh = parseInt(timeParts[0], 10);
  const mm = parseInt(timeParts[1] || "0", 10);
  if ([hh, mm].some((n) => isNaN(n))) return null;
  return madridWallClockToUtcDate(ymd.y, ymd.m, ymd.d, hh, mm);
}

function parseBookingEndDateTime(dayStr, slotStr) {
  const ymd = parseBookingYmd(dayStr);
  const start = parseBookingStartDateTime(dayStr, slotStr);
  if (!ymd || !start) return null;
  if (slotStr.includes("-")) {
    const endStr = slotStr.split("-")[1].trim();
    const endParts = endStr.split(":");
    const endH = parseInt(endParts[0], 10);
    const endM = parseInt(endParts[1] || "0", 10);
    if (isNaN(endH) || isNaN(endM)) return null;
    let end = madridWallClockToUtcDate(ymd.y, ymd.m, ymd.d, endH, endM);
    if (end.getTime() <= start.getTime()) {
      const nextDay = new Date(Date.UTC(ymd.y, ymd.m - 1, ymd.d + 1));
      end = madridWallClockToUtcDate(
        nextDay.getUTCFullYear(),
        nextDay.getUTCMonth() + 1,
        nextDay.getUTCDate(),
        endH,
        endM
      );
    }
    return end;
  }
  return new Date(start.getTime() + 3600 * 1000);
}

async function verifyPaymentIntentIsPaid(stripe, booking) {
  if (!booking) return false;
  if (booking.paymentIntentId) {
    try {
      const pi = await stripe.paymentIntents.retrieve(booking.paymentIntentId);
      return Boolean(pi && pi.status === "succeeded" && String(pi.currency || "eur").toLowerCase() === "eur");
    } catch (e) {
      console.warn(`Could not verify PaymentIntent ${booking.paymentIntentId}:`, e.message);
      return false;
    }
  }
  return booking.paymentStatus === "paid";
}

function generateBookingPin() {
  return String(crypto.randomInt(1000, 10000));
}

function hashPin(pin) {
  return crypto.createHash("sha256").update(String(pin || "").trim()).digest("hex");
}

function computeServerCommissionRate(accumulatedHours, urgencyBonusRate = 0) {
  const hours = Number(accumulatedHours) || 0;
  let baseTierRate = 0.18;
  if (hours >= 40) {
    baseTierRate = 0.06;
  } else if (hours >= 15) {
    baseTierRate = 0.12;
  }
  const safeBonus = Math.min(Math.max(Number(urgencyBonusRate) || 0, 0), 0.05);
  return Math.min(Math.max(baseTierRate - safeBonus, 0.05), 0.25);
}

async function checkRateLimit(key, maxAttempts, windowMs) {
  const db = admin.firestore();
  const safeId = crypto.createHash("sha256").update(String(key)).digest("hex").slice(0, 40);
  const ref = db.collection("rate_limits").doc(safeId);
  const nowMs = Date.now();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    const windowStart = Number(data.windowStartMs) || 0;
    const count = Number(data.count) || 0;
    if (!snap.exists || (nowMs - windowStart) > windowMs) {
      tx.set(ref, { windowStartMs: nowMs, count: 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
      return;
    }
    if (count >= maxAttempts) {
      throw new functions.https.HttpsError("resource-exhausted", "Demasiados intentos en poco tiempo. Espera unos minutos e inténtalo de nuevo.");
    }
    tx.update(ref, { count: count + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  });
}

async function syncCaregiverClientAccess(clientId, caregiverId) {
  if (!clientId || !caregiverId) return;
  const db = admin.firestore();
  const accessRef = db.collection("clients").doc(clientId).collection("caregiver_access").doc(caregiverId);
  try {
    const activeSnap = await db.collection("bookings")
      .where("clientId", "==", clientId)
      .where("caregiverId", "==", caregiverId)
      .where("status", "in", ["pendingPayment", "pending", "confirmed", "disputed"])
      .limit(1)
      .get();
    if (!activeSnap.empty) {
      await accessRef.set({
        caregiverId,
        active: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } else {
      const disputedSnap = await db.collection("bookings")
        .where("clientId", "==", clientId)
        .where("caregiverId", "==", caregiverId)
        .where("escrowStatus", "==", "disputed")
        .limit(1)
        .get();
      if (disputedSnap.empty) {
        await accessRef.delete().catch(() => {});
      }
    }
  } catch (e) {
    console.warn(`syncCaregiverClientAccess(${clientId}, ${caregiverId}) warning:`, e.message);
  }
}

async function acquireEscrowLock(bookingRef, operationName, validateFn) {
  const db = admin.firestore();
  const nowMs = Date.now();
  const lockStaleMs = 2 * 60 * 1000;
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(bookingRef);
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Booking not found.");
    }
    const booking = snap.data() || {};
    const existingLock = booking.escrowLock;
    if (existingLock && existingLock.lockedAtMs && (nowMs - existingLock.lockedAtMs) < lockStaleMs) {
      throw new functions.https.HttpsError("aborted", "Otra operación financiera está procesando esta reserva en este momento. Inténtalo en unos segundos.");
    }
    const validationResult = await validateFn(booking);
    if (validationResult && validationResult.skip) {
      return { acquired: false, booking, ...validationResult };
    }
    tx.update(bookingRef, {
      escrowLock: {
        op: operationName,
        lockedAtMs: nowMs,
      },
    });
    return { acquired: true, booking };
  });
}

async function releaseEscrowLock(bookingRef) {
  try {
    await bookingRef.update({
      escrowLock: admin.firestore.FieldValue.delete(),
    });
  } catch (_) {}
}

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
      const startParts = parts[0].trim().split(':');
      const endParts = parts[1].trim().split(':');
      const startMins = (parseInt(startParts[0], 10) || 0) * 60 + (parseInt(startParts[1] || "0", 10) || 0);
      let endMins = (parseInt(endParts[0], 10) || 0) * 60 + (parseInt(endParts[1] || "0", 10) || 0);
      if (endMins <= startMins) {
        endMins += 24 * 60;
      }
      hours = Math.max(1, Math.round((endMins - startMins) / 60));
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

async function isFamilyMember(familyId, uid) {
  if (!familyId || !uid) return false;
  if (familyId === uid) return true;
  const snap = await admin.firestore().collection("clients").doc(familyId).get();
  if (!snap.exists) return false;
  const data = snap.data() || {};
  if (data.ownerUid === uid) return true;
  if (Array.isArray(data.memberUids) && data.memberUids.includes(uid)) return true;
  return Boolean(data.members && data.members[uid]);
}

async function isFamilyAdmin(familyId, uid) {
  if (!familyId || !uid) return false;
  const snap = await admin.firestore().collection("clients").doc(familyId).get();
  if (!snap.exists) return familyId === uid;
  const data = snap.data() || {};
  if (data.ownerUid === uid) return true;
  if (familyId === uid && !data.ownerUid) return true;
  const member = data.members && data.members[uid];
  if (member && member.role === "admin") return true;
  return false;
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
  const accountId = typeof data?.accountId === "string" ? data.accountId.trim() : "";
  if (!accountId) throw new functions.https.HttpsError("invalid-argument", "accountId requerido.");

  const caregiverSnap = await admin.firestore().collection("caregivers").doc(context.auth.uid).get();
  const ownedAccountId = caregiverSnap.exists ? String(caregiverSnap.data()?.stripeAccountId || "").trim() : "";
  const callerIsAdmin = await isAdminCaller(context);
  if (!callerIsAdmin && (!ownedAccountId || ownedAccountId !== accountId)) {
    throw new functions.https.HttpsError("permission-denied", "No tienes permiso para acceder a esta cuenta Stripe Connect.");
  }

  const stripe = require("stripe")(stripeSecret.value());
  try {
    if (data.mode === "dashboard" || data.type === "login_link") {
      try {
        const loginLink = await stripe.accounts.createLoginLink(accountId);
        return { url: loginLink.url, type: "login_link" };
      } catch (loginError) {
        console.log("Cuenta Express aún en onboarding, generando account_onboarding link:", loginError.message);
      }
    }
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: "https://senicare-3342d.web.app/?stripe=reauth",
      return_url: "https://senicare-3342d.web.app/?stripe=return",
      type: "account_onboarding",
    });
    return { url: accountLink.url, type: "account_onboarding" };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
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


const PAYMENT_PREFERENCE_METHOD_TYPES = {
  card: ["card"],
  card_link: ["card", "link"],
  link: ["link", "card"],
  klarna: ["klarna"],
  sepa_debit: ["sepa_debit"],
  revolut_pay: ["revolut_pay"],
  bizum: ["bizum"],
};

async function getOrCreateStripeCustomerAndSession(stripe, auth) {
  const uid = auth?.uid;
  if (!uid) return {};
  try {
    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    let customerId = userSnap.exists ? userSnap.data()?.stripeCustomerId : null;

    if (!customerId) {
      const tokenEmail = auth.token?.email || userSnap.data()?.email || undefined;
      const tokenName = auth.token?.name || userSnap.data()?.name || undefined;
      const customer = await stripe.customers.create({
        email: tokenEmail,
        name: tokenName,
        metadata: { firebaseUid: uid },
      });
      customerId = customer.id;
      await userRef.set({ stripeCustomerId: customerId }, { merge: true });
    }

    let customerSessionClientSecret = null;
    try {
      const customerSession = await stripe.customerSessions.create({
        customer: customerId,
        components: {
          mobile_payment_element: {
            enabled: true,
            features: {
              payment_method_save: "enabled",
              payment_method_redisplay: "enabled",
              payment_method_remove: "enabled",
            },
          },
        },
      });
      customerSessionClientSecret = customerSession.client_secret;
    } catch (csErr) {
      console.warn("CustomerSession creation warning:", csErr.message);
    }

    let ephemeralKeySecret = null;
    if (!customerSessionClientSecret) {
      try {
        const ephemeralKey = await stripe.ephemeralKeys.create(
          { customer: customerId },
          { apiVersion: "2024-06-20" }
        );
        ephemeralKeySecret = ephemeralKey.secret;
      } catch (ekErr) {
        console.warn("EphemeralKey creation warning:", ekErr.message);
      }
    }

    return {
      customerId,
      customerSessionClientSecret,
      ephemeralKeySecret,
    };
  } catch (e) {
    console.warn("getOrCreateStripeCustomerAndSession skipped:", e.message);
    return {};
  }
}

async function createPaymentIntentWithPreference(
  stripe,
  {
    amountInCents,
    currency = "eur",
    transferGroup,
    preferredMethod = "auto",
    customerId = null,
    metadata = {},
    description = null,
  }
) {
  const normalizedMethod = String(preferredMethod || "auto").toLowerCase().trim();
  const baseParams = {
    amount: Math.max(50, Math.round(Number(amountInCents) || 0)),
    currency: String(currency || "eur").toLowerCase(),
    transfer_group: transferGroup,
    metadata: { ...metadata, preferredMethod: normalizedMethod },
  };
  if (customerId) baseParams.customer = customerId;
  if (description) baseParams.description = description;

  const explicitTypes = PAYMENT_PREFERENCE_METHOD_TYPES[normalizedMethod];
  if (explicitTypes && explicitTypes.length > 0) {
    try {
      const paymentIntent = await stripe.paymentIntents.create({
        ...baseParams,
        payment_method_types: explicitTypes,
      });
      return {
        paymentIntent,
        requestedMethod: normalizedMethod,
        fallbackUsed: false,
      };
    } catch (explicitErr) {
      console.warn(
        `Preferred method '${normalizedMethod}' fallback to automatic_payment_methods:`,
        explicitErr.message
      );
      const fallbackIntent = await stripe.paymentIntents.create({
        ...baseParams,
        automatic_payment_methods: { enabled: true },
      });
      return {
        paymentIntent: fallbackIntent,
        requestedMethod: normalizedMethod,
        fallbackUsed: true,
      };
    }
  }

  const autoParams = {
    ...baseParams,
    automatic_payment_methods:
      normalizedMethod === "wallet"
        ? { enabled: true, allow_redirects: "never" }
        : { enabled: true },
  };
  try {
    const paymentIntent = await stripe.paymentIntents.create(autoParams);
    return {
      paymentIntent,
      requestedMethod: normalizedMethod,
      fallbackUsed: false,
    };
  } catch (autoErr) {
    console.warn("automatic_payment_methods fallback to ['card']:", autoErr.message);
    const cardIntent = await stripe.paymentIntents.create({
      ...baseParams,
      payment_method_types: ["card"],
    });
    return {
      paymentIntent: cardIntent,
      requestedMethod: normalizedMethod,
      fallbackUsed: true,
    };
  }
}

function extractStripePaymentMethodType(paymentIntent) {
  try {
    const details = paymentIntent?.latest_charge?.payment_method_details;
    if (details?.card?.wallet?.type) {
      return details.card.wallet.type;
    }
    if (details?.type) {
      return details.type;
    }
    if (Array.isArray(paymentIntent?.payment_method_types) && paymentIntent.payment_method_types.length > 0) {
      return paymentIntent.payment_method_types[0];
    }
  } catch (_) {}
  return "card";
}

exports.createSecureBooking = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
    const uid = context.auth.uid;
    await checkRateLimit(`booking:${uid}`, 12, 10 * 60 * 1000);

    const targetFamilyId = (typeof data?.familyId === "string" && data.familyId.trim()) ? data.familyId.trim() : uid;
    if (!(await isFamilyAdmin(targetFamilyId, uid))) {
      throw new functions.https.HttpsError("permission-denied", "Solo un Administrador familiar puede crear reservas de pago.");
    }

    const stripe = require("stripe")(stripeSecret.value());
    const db = admin.firestore();
    const caregiverId = typeof data?.caregiverId === "string" ? data.caregiverId.trim() : "";
    if (!caregiverId) {
      throw new functions.https.HttpsError("invalid-argument", "caregiverId requerido.");
    }

    const offerId = typeof data?.offerId === "string" && data.offerId.trim() ? data.offerId.trim() : null;
    const applicationId = typeof data?.applicationId === "string" && data.applicationId.trim() ? data.applicationId.trim() : null;
    if ((offerId && !applicationId) || (!offerId && applicationId)) {
      throw new functions.https.HttpsError("invalid-argument", "offerId y applicationId deben proporcionarse juntos.");
    }

    const rawSessions = Array.isArray(data?.sessions) && data.sessions.length > 0
      ? data.sessions
      : (data?.day && data?.slot ? [{ day: data.day, slot: data.slot, totalHours: data.totalHours }] : []);
    if (rawSessions.length === 0 || rawSessions.length > 60) {
      throw new functions.https.HttpsError("invalid-argument", "Se requiere al menos una sesión válida (máx. 60).");
    }

    const normalizedSessions = [];
    for (const s of rawSessions) {
      const day = String(s?.day || "").trim();
      const slot = String(s?.slot || "").trim();
      if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) {
        throw new functions.https.HttpsError("invalid-argument", `Fecha de sesión inválida: ${day}`);
      }
      const startDt = parseBookingStartDateTime(day, slot);
      const endDt = parseBookingEndDateTime(day, slot);
      if (!startDt || !endDt || endDt.getTime() <= startDt.getTime()) {
        throw new functions.https.HttpsError("invalid-argument", `Franja horaria inválida: ${slot}`);
      }
      const parsedHours = (endDt.getTime() - startDt.getTime()) / (3600 * 1000);
      if (!Number.isFinite(parsedHours) || parsedHours < 1 || parsedHours > 24) {
        throw new functions.https.HttpsError("invalid-argument", `Duración de sesión inválida: ${slot}`);
      }
      normalizedSessions.push({
        day,
        slot,
        hours: Math.round(parsedHours * 100) / 100,
        startHour: startDt.getHours(),
        endHour: endDt.getHours() === 0 && endDt.getDate() !== startDt.getDate() ? 24 : endDt.getHours(),
      });
    }

    const sanitizedChecklist = Array.isArray(data?.checklist)
      ? data.checklist.slice(0, 30).map((item, idx) => {
          const title = typeof item === "string" ? item.trim() : String(item?.title || "").trim();
          return title ? { id: `task_${idx + 1}`, title: title.slice(0, 200), isCompleted: false } : null;
        }).filter(Boolean)
      : [];

    let createdPaymentIntentId = null;
    try {
        const caregiverDoc = await db.collection("caregivers").doc(caregiverId).get();
        if (!caregiverDoc.exists) throw new functions.https.HttpsError("not-found", "Cuidador no encontrado.");
        const caregiverData = caregiverDoc.data() || {};
        if (caregiverData.verificationStatus !== "approved") {
          throw new functions.https.HttpsError("failed-precondition", "El cuidador aún no está verificado y aprobado.");
        }
        if (caregiverData.status === "suspended" || caregiverData.accountStatus === "suspended") {
          throw new functions.https.HttpsError("failed-precondition", "El cuidador no está disponible actualmente.");
        }
        if (caregiverData.blockedUntil && caregiverData.blockedUntil.toDate() > new Date()) {
          throw new functions.https.HttpsError("failed-precondition", "El cuidador tiene una suspensión temporal activa.");
        }

        const caregiverName = caregiverData.name || "Cuidador SeniCare";
        const stripeAccountId = String(caregiverData.stripeAccountId || "").trim();
        if (!stripeAccountId) {
          throw new functions.https.HttpsError("failed-precondition", "El cuidador no tiene cuenta de cobro configurada.");
        }

        let pricePerHour = Number(caregiverData.pricePerHour) || 0;
        let clientFeeRate = STANDARD_CLIENT_FEE_RATE;
        let urgencyBonusRate = 0.0;
        let offerTitle = `Cuidado con ${caregiverName}`;

        if (offerId && applicationId) {
            const offerDoc = await db.collection("job_offers").doc(offerId).get();
            if (!offerDoc.exists) throw new functions.https.HttpsError("not-found", "Oferta de empleo no encontrada.");
            const offerData = offerDoc.data() || {};
            if (offerData.clientId !== targetFamilyId) {
              throw new functions.https.HttpsError("permission-denied", "Esta oferta no pertenece a tu familia.");
            }
            if (offerData.status !== "open") {
              throw new functions.https.HttpsError("failed-precondition", "La oferta ya no está abierta.");
            }
            const appDoc = await db.collection("job_offers").doc(offerId).collection("applications").doc(applicationId).get();
            if (!appDoc.exists) throw new functions.https.HttpsError("not-found", "Candidatura no encontrada.");
            const appData = appDoc.data() || {};
            if (appData.caregiverId !== caregiverId || appData.status === "rejected") {
              throw new functions.https.HttpsError("failed-precondition", "La candidatura seleccionada no es válida.");
            }
            pricePerHour = Number(appData.proposedPrice) || Number(caregiverData.pricePerHour) || 0;
            const rawFeeRate = Number(offerData.clientFeeRate);
            clientFeeRate = (Number.isFinite(rawFeeRate) && rawFeeRate >= STANDARD_CLIENT_FEE_RATE && rawFeeRate <= 0.15)
              ? rawFeeRate
              : STANDARD_CLIENT_FEE_RATE;
            const rawUrgency = Number(offerData.urgencyBonusRate);
            urgencyBonusRate = Number.isFinite(rawUrgency) ? Math.min(Math.max(rawUrgency, 0), 0.05) : 0.0;
            if (offerData.title) offerTitle = String(offerData.title).trim().slice(0, 100);
        }

        if (!Number.isFinite(pricePerHour) || pricePerHour < 6 || pricePerHour > 200) {
          throw new functions.https.HttpsError("failed-precondition", "La tarifa por hora del cuidador no es válida.");
        }

        const [statsDoc, clientDoc] = await Promise.all([
          db.collection("client_caregiver_stats").doc(`${targetFamilyId}_${caregiverId}`).get(),
          db.collection("clients").doc(targetFamilyId).get(),
        ]);
        const accumulatedHours = statsDoc.exists ? (Number(statsDoc.data()?.accumulatedHours) || 0) : 0;
        const commissionRate = computeServerCommissionRate(accumulatedHours, urgencyBonusRate);

        const clientData = clientDoc.exists ? clientDoc.data() || {} : {};
        const lat = Number.isFinite(Number(clientData.latitude))
          ? Number(clientData.latitude)
          : (Number.isFinite(Number(data?.clientLatitude)) ? Number(data.clientLatitude) : null);
        const lng = Number.isFinite(Number(clientData.longitude))
          ? Number(clientData.longitude)
          : (Number.isFinite(Number(data?.clientLongitude)) ? Number(data.clientLongitude) : null);

        const totalRequestedHours = normalizedSessions.reduce((acc, s) => acc + s.hours, 0);
        const discountMultiplier = (!offerId && totalRequestedHours >= 4) ? 0.95 : 1.0;

        const transferGroup = `${offerId ? `offer_${offerId}` : "booking"}_${Date.now()}`;
        const sharedPin = generateBookingPin();
        const sharedPinHash = hashPin(sharedPin);
        const qrToken = crypto.randomBytes(16).toString("hex");
        const preferredMethod = typeof data?.preferredMethod === "string" ? data.preferredMethod.toLowerCase().trim() : "auto";
        const useCheckoutSession = data?.useCheckoutSession === true || preferredMethod === "bizum";

        let totalPaidOverall = 0;
        const bookingsToCreate = [];
        const bookingIds = [];

        for (const session of normalizedSessions) {
            const cost = Math.round(pricePerHour * session.hours * discountMultiplier * 100) / 100;
            const clientFee = Math.round(cost * clientFeeRate * 100) / 100;
            const commissionAmount = Math.round(cost * commissionRate * 100) / 100;
            const caregiverPayout = Math.round((cost - commissionAmount) * 100) / 100;
            const totalPaid = Math.round((cost + clientFee) * 100) / 100;

            totalPaidOverall += totalPaid;
            const bookingRef = db.collection("bookings").doc();
            bookingIds.push(bookingRef.id);
            bookingsToCreate.push({
                ref: bookingRef,
                secretRef: bookingRef.collection("secrets").doc("checkin"),
                session,
                data: {
                    id: bookingRef.id,
                    clientId: targetFamilyId,
                    caregiverId,
                    caregiverName,
                    day: session.day,
                    slot: session.slot,
                    clientLatitude: lat,
                    clientLongitude: lng,
                    cost,
                    clientFee,
                    clientFeeRate,
                    offerId: offerId || null,
                    applicationId: applicationId || null,
                    isJobOffer: Boolean(offerId),
                    caregiverCommissionRate: commissionRate,
                    caregiverCommissionAmount: commissionAmount,
                    caregiverPayout,
                    totalPaid,
                    discountApplied: discountMultiplier < 1.0,
                    bookingPinHash: sharedPinHash,
                    careChecklist: sanitizedChecklist,
                    status: "pendingPayment",
                    paymentStatus: "pending",
                    transferGroup,
                    escrowStatus: "none",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    isReviewed: false,
                },
            });
        }

        const amountInCents = Math.round(totalPaidOverall * 100);
        if (amountInCents < 50) {
          throw new functions.https.HttpsError("invalid-argument", "El importe mínimo es 0,50 €.");
        }

        const customerInfo = await getOrCreateStripeCustomerAndSession(stripe, context.auth);
        let responsePayload = {};
        let resolvedMethod = preferredMethod;

        if (useCheckoutSession) {
          const projectId = process.env.GCLOUD_PROJECT || "senicare-3342d";
          const returnBaseUrl = `https://europe-west1-${projectId}.cloudfunctions.net/stripeCheckoutRedirect`;
          const bookingIdsStr = bookingIds.join(",").slice(0, 450);
          const sessionBase = {
            mode: "payment",
            locale: "es",
            customer: customerInfo.customerId || undefined,
            line_items: [
              {
                price_data: {
                  currency: "eur",
                  product_data: {
                    name: offerTitle,
                    description: "Pago protegido en custodia bancaria (Stripe Escrow) · SeniCare",
                  },
                  unit_amount: amountInCents,
                },
                quantity: 1,
              },
            ],
            payment_intent_data: {
              transfer_group: transferGroup,
              metadata: {
                familyId: targetFamilyId,
                paidByUid: uid,
                caregiverId,
                offerId: offerId || "",
                preferredMethod,
                bookingIds: bookingIdsStr,
              },
            },
            metadata: {
              familyId: targetFamilyId,
              paidByUid: uid,
              caregiverId,
              offerId: offerId || "",
              preferredMethod,
              bookingIds: bookingIdsStr,
            },
            success_url: `${returnBaseUrl}?status=success&session_id={CHECKOUT_SESSION_ID}`,
            cancel_url: `${returnBaseUrl}?status=cancelled&session_id={CHECKOUT_SESSION_ID}`,
          };

          let session;
          let fallbackUsed = false;
          try {
            const methodList = PAYMENT_PREFERENCE_METHOD_TYPES[preferredMethod];
            session = await stripe.checkout.sessions.create({
              ...sessionBase,
              ...(methodList ? { payment_method_types: methodList } : {}),
            });
          } catch (explicitErr) {
            console.warn(`Secure checkout '${preferredMethod}' fallback:`, explicitErr.message);
            fallbackUsed = true;
            session = await stripe.checkout.sessions.create(sessionBase);
          }

          createdPaymentIntentId = typeof session.payment_intent === "string"
            ? session.payment_intent
            : session.payment_intent?.id || null;
          responsePayload = {
            sessionId: session.id,
            url: session.url,
            paymentIntentId: createdPaymentIntentId,
            transferGroup,
            requestedMethod: preferredMethod,
            fallbackUsed,
          };
        } else {
          const bookingIdsStr = bookingIds.join(",").slice(0, 450);
          const {
            paymentIntent,
            requestedMethod,
            fallbackUsed,
          } = await createPaymentIntentWithPreference(stripe, {
            amountInCents,
            currency: "eur",
            transferGroup,
            preferredMethod,
            customerId: customerInfo.customerId,
            metadata: {
              familyId: targetFamilyId,
              paidByUid: uid,
              caregiverId,
              offerId: offerId || "",
              bookingIds: bookingIdsStr,
            },
            description: offerId ? `SeniCare · ${offerTitle}` : `SeniCare · Cuidado con ${caregiverName}`,
          });
          createdPaymentIntentId = paymentIntent.id;
          resolvedMethod = requestedMethod;
          responsePayload = {
            clientSecret: paymentIntent.client_secret,
            paymentIntentId: paymentIntent.id,
            transferGroup,
            customerId: customerInfo.customerId || null,
            customerSessionClientSecret: customerInfo.customerSessionClientSecret || null,
            ephemeralKeySecret: customerInfo.ephemeralKeySecret || null,
            requestedMethod,
            fallbackUsed,
          };
        }

        // Persist bookings, secrets, caregiver client access and slot locks atomically
        await db.runTransaction(async (tx) => {
          const slotChecks = [];
          if (!offerId) {
            for (const item of bookingsToCreate) {
              const { day, startHour, endHour } = item.session;
              for (let h = startHour; h < endHour; h++) {
                const hh = String(h).padStart(2, "0") + ":00";
                const slotDocId = `${day}_${hh}`;
                const slotRef = db.collection("caregivers").doc(caregiverId)
                  .collection("availability").doc(day)
                  .collection("slots").doc(slotDocId);
                slotChecks.push({ slotRef, hh, day, slotDocId, bookingId: item.ref.id });
              }
            }
          }

          const slotSnaps = await Promise.all(slotChecks.map((sc) => tx.get(sc.slotRef)));
          for (let i = 0; i < slotChecks.length; i++) {
            const snap = slotSnaps[i];
            if (snap.exists && snap.data()?.isAvailable === false) {
              throw new functions.https.HttpsError(
                "failed-precondition",
                `La hora ${slotChecks[i].hh} (${slotChecks[i].day}) ya no está disponible. Elige otro horario.`
              );
            }
          }

          for (let i = 0; i < slotChecks.length; i++) {
            const sc = slotChecks[i];
            tx.set(sc.slotRef, {
              id: sc.slotDocId,
              isAvailable: false,
              lockedByBookingId: sc.bookingId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }

          for (const item of bookingsToCreate) {
            if (createdPaymentIntentId) item.data.paymentIntentId = createdPaymentIntentId;
            item.data.paymentMethodType = resolvedMethod;
            tx.set(item.ref, item.data);
            tx.set(item.secretRef, {
              bookingPin: sharedPin,
              qrToken,
              clientId: targetFamilyId,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          tx.set(
            db.collection("clients").doc(targetFamilyId).collection("caregiver_access").doc(caregiverId),
            {
              caregiverId,
              active: true,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        });

        return {
          ...responsePayload,
          bookingIds,
          bookingPin: sharedPin,
          totalEur: Math.round(totalPaidOverall * 100) / 100,
          discountApplied: discountMultiplier < 1.0,
          commissionRate,
        };
    } catch (error) {
        if (createdPaymentIntentId) {
          try {
            await stripe.paymentIntents.cancel(createdPaymentIntentId);
          } catch (_) {}
        }
        if (error instanceof functions.https.HttpsError) throw error;
        console.error("Secure Booking Error: ", error);
        throw new functions.https.HttpsError("internal", error.message);
    }
});

exports.createPaymentIntent = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  await checkRateLimit(`pi:${uid}`, 12, 10 * 60 * 1000);

  const familyId = (typeof data?.familyId === "string" && data.familyId.trim()) ? data.familyId.trim() : uid;
  if (!(await isFamilyAdmin(familyId, uid)) && !(await isAdminCaller(context))) {
    throw new functions.https.HttpsError("permission-denied", "Solo un Administrador familiar puede iniciar pagos.");
  }

  const bookingIds = Array.isArray(data?.bookingIds)
    ? data.bookingIds.map((b) => String(b).trim()).filter(Boolean)
    : [];
  if (bookingIds.length === 0) {
    throw new functions.https.HttpsError("failed-precondition", "Usa createSecureBooking con reservas registradas en el servidor.");
  }

  const db = admin.firestore();
  const docs = await Promise.all(bookingIds.map((id) => db.collection("bookings").doc(id).get()));
  let computedTotalEur = 0;
  let transferGroup = `booking_${Date.now()}`;
  let caregiverId = "";
  for (const snap of docs) {
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    const b = snap.data() || {};
    if (b.clientId !== familyId) throw new functions.https.HttpsError("permission-denied", "La reserva no pertenece a esta familia.");
    if (b.paymentStatus === "paid") throw new functions.https.HttpsError("failed-precondition", "La reserva ya está pagada.");
    computedTotalEur += Number(b.totalPaid) || ((Number(b.cost) || 0) * (1 + (Number(b.clientFeeRate) || STANDARD_CLIENT_FEE_RATE)));
    if (b.transferGroup) transferGroup = b.transferGroup;
    if (b.caregiverId) caregiverId = b.caregiverId;
  }

  const amountInCents = Math.round(computedTotalEur * 100);
  if (!Number.isFinite(amountInCents) || amountInCents < 50) {
    throw new functions.https.HttpsError("invalid-argument", "El importe mínimo es 0,50 €.");
  }

  const stripe = require("stripe")(stripeSecret.value());
  try {
    const preferredMethod = typeof data?.preferredMethod === "string" ? data.preferredMethod : "auto";
    const customerInfo = await getOrCreateStripeCustomerAndSession(stripe, context.auth);
    const {
      paymentIntent,
      requestedMethod,
      fallbackUsed,
    } = await createPaymentIntentWithPreference(stripe, {
      amountInCents,
      currency: "eur",
      transferGroup,
      preferredMethod,
      customerId: customerInfo.customerId,
      metadata: {
        familyId,
        paidByUid: uid,
        caregiverId,
        bookingIds: bookingIds.join(",").slice(0, 450),
      },
      description:
        typeof data?.description === "string" && data.description.trim()
          ? data.description.trim().slice(0, 120)
          : "SeniCare · Reserva de cuidado",
    });

    const batch = db.batch();
    for (const snap of docs) {
      batch.update(snap.ref, { paymentIntentId: paymentIntent.id });
    }
    await batch.commit();

    return {
      clientSecret: paymentIntent.client_secret,
      transferGroup: paymentIntent.transfer_group,
      paymentIntentId: paymentIntent.id,
      customerId: customerInfo.customerId || null,
      customerSessionClientSecret: customerInfo.customerSessionClientSecret || null,
      ephemeralKeySecret: customerInfo.ephemeralKeySecret || null,
      requestedMethod,
      fallbackUsed,
    };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Stripe Error Details: ", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

async function reopenBookingSlots(caregiverId, day, slotRange) {
  if (!caregiverId || !day || !slotRange) return;
  try {
    const cgRef = admin.firestore().collection("caregivers").doc(caregiverId).collection("availability");
    const formatYmd = (dateObj) => {
      const y = dateObj.getFullYear();
      const m = String(dateObj.getMonth() + 1).padStart(2, "0");
      const d = String(dateObj.getDate()).padStart(2, "0");
      return `${y}-${m}-${d}`;
    };

    const startDt = parseBookingStartDateTime(day, slotRange);
    const endDt = parseBookingEndDateTime(day, slotRange);
    if (slotRange.includes("-") && startDt && endDt && endDt.getTime() > startDt.getTime()) {
      const batch = admin.firestore().batch();
      const totalHours = Math.min(24, Math.max(1, Math.round((endDt.getTime() - startDt.getTime()) / (3600 * 1000))));
      for (let i = 0; i < totalHours; i++) {
        const current = new Date(startDt.getTime() + i * 3600 * 1000);
        const dayStr = formatYmd(current);
        const hourStr = `${String(current.getHours()).padStart(2, "0")}:00`;
        const prefixedId = `${dayStr}_${hourStr}`;
        const slotsRef = cgRef.doc(dayStr).collection("slots");
        const legacyRef = slotsRef.doc(hourStr);
        const legacySnap = await legacyRef.get();
        if (legacySnap.exists) {
          batch.set(legacyRef, { isAvailable: true }, { merge: true });
        }
        batch.set(slotsRef.doc(prefixedId), {
          dateTime: admin.firestore.Timestamp.fromDate(current),
          isAvailable: true,
        }, { merge: true });
      }
      await batch.commit();
      return;
    }
    await cgRef.doc(day).collection("slots").doc(`${day}_${slotRange}`).set({ isAvailable: true }, { merge: true });
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

exports.verifyBookingCheckIn = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const bookingId = typeof data?.bookingId === "string" ? data.bookingId.trim() : "";
  if (!bookingId) throw new functions.https.HttpsError("invalid-argument", "bookingId requerido.");

  await checkRateLimit(`checkin:${uid}:${bookingId}`, 10, 10 * 60 * 1000);

  const method = data?.method === "qr" ? "qr" : "pin";
  const db = admin.firestore();
  const bookingRef = db.collection("bookings").doc(bookingId);
  const [bookingSnap, secretSnap] = await Promise.all([
    bookingRef.get(),
    bookingRef.collection("secrets").doc("checkin").get(),
  ]);

  if (!bookingSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
  }
  const booking = bookingSnap.data() || {};
  if (booking.caregiverId !== uid) {
    throw new functions.https.HttpsError("permission-denied", "Solo el cuidador asignado puede registrar el check-in.");
  }
  if (booking.checkInTime) {
    return { success: true, alreadyCheckedIn: true };
  }
  if (booking.status !== "confirmed") {
    throw new functions.https.HttpsError("failed-precondition", "La reserva debe estar confirmada para hacer check-in.");
  }
  if (booking.paymentStatus !== "paid" && booking.paymentStatus !== "processing") {
    throw new functions.https.HttpsError("failed-precondition", "El pago de la reserva aún no está autorizado.");
  }

  const startDt = parseBookingStartDateTime(booking.day, booking.slot);
  const endDt = parseBookingEndDateTime(booking.day, booking.slot);
  if (startDt && endDt) {
    // Cloud Functions run in UTC; bookings are scheduled in Europe/Madrid local time (+1h/+2h)
    const nowMs = Date.now();
    const minAllowedMs = startDt.getTime() - (150 * 60 * 1000);
    const maxAllowedMs = endDt.getTime() + (30 * 60 * 1000);
    if (nowMs < minAllowedMs) {
      throw new functions.https.HttpsError("failed-precondition", "Aún es demasiado pronto para fichar el inicio de este servicio.");
    }
    if (nowMs > maxAllowedMs) {
      throw new functions.https.HttpsError("failed-precondition", "La ventana horaria de este servicio ya ha finalizado.");
    }
  }

  const secretData = secretSnap.exists ? secretSnap.data() || {} : {};

  if (method === "pin") {
    const enteredPin = String(data?.pin || "").trim();
    if (!/^\d{4}$/.test(enteredPin)) {
      throw new functions.https.HttpsError("invalid-argument", "Introduce un PIN válido de 4 dígitos.");
    }
    const storedHash = String(booking.bookingPinHash || "");
    const enteredHash = hashPin(enteredPin);
    const plainFallback = String(secretData.bookingPin || booking.bookingPin || "").trim();
    const hashMatches = storedHash.length === enteredHash.length &&
      storedHash.length > 0 &&
      crypto.timingSafeEqual(Buffer.from(storedHash), Buffer.from(enteredHash));
    const plainMatches = plainFallback.length === 4 &&
      crypto.timingSafeEqual(Buffer.from(plainFallback), Buffer.from(enteredPin));
    if (!hashMatches && !plainMatches) {
      throw new functions.https.HttpsError("permission-denied", "PIN incorrecto. Comprueba los 4 dígitos facilitados por la familia.");
    }
  } else {
    const qrValue = String(data?.qrValue || "").trim();
    const validQr = qrValue === bookingId ||
      qrValue === `booking_qr_${bookingId}` ||
      qrValue === `client_qr_${booking.clientId}` ||
      (secretData.qrToken && qrValue === String(secretData.qrToken));
    if (!validQr) {
      throw new functions.https.HttpsError("permission-denied", "Código QR inválido. No corresponde a esta familia o reserva.");
    }
    const clientLat = Number(booking.clientLatitude);
    const clientLng = Number(booking.clientLongitude);
    const cgLat = Number(data?.latitude);
    const cgLng = Number(data?.longitude);
    if (Number.isFinite(clientLat) && Number.isFinite(clientLng)) {
      if (!Number.isFinite(cgLat) || !Number.isFinite(cgLng)) {
        throw new functions.https.HttpsError("failed-precondition", "Se requiere ubicación GPS válida para el check-in por QR.");
      }
      const dLat = (cgLat - clientLat) * Math.PI / 180;
      const dLon = (cgLng - clientLng) * Math.PI / 180;
      const a = Math.sin(dLat / 2) ** 2 +
        Math.cos(clientLat * Math.PI / 180) * Math.cos(cgLat * Math.PI / 180) * (Math.sin(dLon / 2) ** 2);
      const distMeters = 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      const accuracy = Math.max(0, Number(data?.accuracy) || 0);
      if (distMeters > 300 && (distMeters - accuracy) > 200) {
        throw new functions.https.HttpsError("failed-precondition", `Están a ${Math.round(distMeters)}m del domicilio. Acércate al domicilio o usa el código PIN.`);
      }
    }
  }

  let isPunctual = true;
  if (startDt) {
    // Conservatively treat > 15m after UTC/local margin only when verifiable cleanly; cron computes final payout adjustment
    isPunctual = (Date.now() - startDt.getTime()) <= (15 * 60 * 1000);
  }

  await bookingRef.update({
    checkInTime: admin.firestore.FieldValue.serverTimestamp(),
    checkInMethod: method,
    isPunctual,
    liveStatus: "in_progress",
  });

  return { success: true, checkInMethod: method };
});

exports.cancelPendingCheckout = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const bookingIds = Array.isArray(data?.bookingIds)
    ? data.bookingIds.map((id) => String(id).trim()).filter(Boolean)
    : [];
  if (bookingIds.length === 0) return { success: true, cleaned: 0 };

  const stripe = require("stripe")(stripeSecret.value());
  const db = admin.firestore();
  const cancelledIntents = new Set();
  const pairsToSync = [];
  let cleaned = 0;

  for (const id of bookingIds.slice(0, 60)) {
    const ref = db.collection("bookings").doc(id);
    const snap = await ref.get();
    if (!snap.exists) continue;
    const b = snap.data() || {};
    if (!(await isFamilyAdmin(b.clientId, uid)) && !(await isAdminCaller(context))) {
      continue;
    }
    if (b.status !== "pendingPayment" || b.paymentStatus === "paid") {
      continue;
    }
    if (b.paymentIntentId && !cancelledIntents.has(b.paymentIntentId)) {
      cancelledIntents.add(b.paymentIntentId);
      try {
        const pi = await stripe.paymentIntents.retrieve(b.paymentIntentId);
        if (pi && ["requires_payment_method", "requires_confirmation", "requires_action"].includes(pi.status)) {
          await stripe.paymentIntents.cancel(b.paymentIntentId);
        } else if (pi && (pi.status === "succeeded" || pi.status === "processing")) {
          // Do not delete an already authorized/processing payment
          continue;
        }
      } catch (_) {}
    }
    await reopenBookingSlots(b.caregiverId, b.day, b.slot);
    await ref.collection("secrets").doc("checkin").delete().catch(() => {});
    await ref.delete();
    pairsToSync.push([b.clientId, b.caregiverId]);
    cleaned++;
  }

  for (const [cId, cgId] of pairsToSync) {
    await syncCaregiverClientAccess(cId, cgId);
  }
  return { success: true, cleaned };
});

exports.releaseEscrowPayment = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  const bookingId = data?.bookingId;
  if (!bookingId) throw new functions.https.HttpsError("invalid-argument", "bookingId is required.");

  const db = admin.firestore();
  const bookingRef = db.collection("bookings").doc(bookingId);
  let lockAcquired = false;

  try {
    const callerIsAdmin = await isAdminCaller(context);
    const lockResult = await acquireEscrowLock(bookingRef, "releaseEscrowPayment", async (booking) => {
      if (!(await isFamilyAdmin(booking.clientId, context.auth.uid)) && !callerIsAdmin) {
        throw new functions.https.HttpsError("permission-denied", "No autorizado para liberar este pago.");
      }
      if (booking.escrowStatus !== "held" && booking.escrowStatus !== "pending") {
        throw new functions.https.HttpsError("failed-precondition", "El pago ya ha sido liberado o reembolsado.");
      }
      if (!booking.checkInTime && !callerIsAdmin) {
        throw new functions.https.HttpsError("failed-precondition", "No se puede liberar el pago: el cuidador no ha realizado el Check-in (no se ha presentado en el domicilio).");
      }
      return {};
    });
    lockAcquired = lockResult.acquired;
    const booking = lockResult.booking;

    const isPaid = await verifyPaymentIntentIsPaid(stripe, booking);
    if (!isPaid) {
      throw new functions.https.HttpsError("failed-precondition", "El pago aún está pendiente de confirmación bancaria (p. ej. SEPA en curso) y no puede liberarse todavía.");
    }

    const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
    if (!caregiverDoc.exists || !caregiverDoc.data().stripeAccountId) {
      throw new functions.https.HttpsError("failed-precondition", "El cuidador no tiene cuenta de Stripe configurada.");
    }

    const destinationAccountId = caregiverDoc.data().stripeAccountId;
    const amountInCents = Math.round((Number(booking.caregiverPayout) || 0) * 100);
    if (amountInCents <= 0) {
      throw new functions.https.HttpsError("failed-precondition", "El importe a transferir no es válido.");
    }

    const transfer = await createLinkedStripeTransfer(stripe, {
      amountInCents,
      destination: destinationAccountId,
      paymentIntentId: booking.paymentIntentId,
      transferGroup: booking.transferGroup,
      idempotencyKey: `release_${bookingId}`,
    });

    await bookingRef.update({
      escrowStatus: "released_manual",
      status: "completed",
      paymentStatus: "paid",
      escrowLock: admin.firestore.FieldValue.delete(),
    });
    lockAcquired = false;

    await Promise.all([
      addCompletedHours(booking.clientId, booking.caregiverId, booking.slot),
      syncCaregiverClientAccess(booking.clientId, booking.caregiverId),
    ]);

    return { transferId: transfer.id, success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Error in releaseEscrowPayment:", error);
    throw new functions.https.HttpsError("internal", error.message);
  } finally {
    if (lockAcquired) await releaseEscrowLock(bookingRef);
  }
});

exports.cancelBookingProcess = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  const { bookingId, reason } = data || {};
  if (!bookingId) throw new functions.https.HttpsError("invalid-argument", "bookingId is required.");

  const db = admin.firestore();
  const bookingRef = db.collection("bookings").doc(bookingId);
  let lockAcquired = false;

  try {
    const callerIsAdmin = await isAdminCaller(context);
    let callerIsCaregiver = false;
    let callerIsFamily = false;
    const settledEscrowStatuses = ["released", "released_manual", "released_auto", "resolved_partial", "refunded"];

    const lockResult = await acquireEscrowLock(bookingRef, "cancelBookingProcess", async (booking) => {
      callerIsCaregiver = booking.caregiverId === context.auth.uid;
      callerIsFamily = await isFamilyAdmin(booking.clientId, context.auth.uid);
      if (!callerIsCaregiver && !callerIsFamily && !callerIsAdmin) {
        throw new functions.https.HttpsError("permission-denied", "No autorizado para cancelar esta reserva.");
      }
      if (booking.status === "cancelled" || booking.status === "cancelledLate" || booking.escrowStatus === "refunded") {
        return { skip: true, alreadyCancelled: true };
      }
      if (booking.status === "completed" || settledEscrowStatuses.includes(booking.escrowStatus)) {
        throw new functions.https.HttpsError("failed-precondition", "No se puede cancelar una reserva ya completada o liquidada.");
      }
      if (booking.checkInTime && !callerIsAdmin) {
        throw new functions.https.HttpsError("failed-precondition", "El servicio ya ha comenzado con Check-in. Abre una disputa si existe una incidencia.");
      }
      return {};
    });

    if (!lockResult.acquired) {
      return { success: true, alreadyCancelled: true };
    }
    lockAcquired = true;
    const booking = lockResult.booking;

    let serverIsLate = false;
    if (!callerIsCaregiver && booking.status === "confirmed") {
      const startDt = parseBookingStartDateTime(booking.day, booking.slot);
      if (startDt) {
        const hoursUntilStart = (startDt.getTime() - Date.now()) / (3600 * 1000);
        serverIsLate = hoursUntilStart < 24;
      } else if (data?.isLate === true && callerIsAdmin) {
        serverIsLate = true;
      }
    }

    const isPaid = await verifyPaymentIntentIsPaid(stripe, booking);

    if (callerIsCaregiver || booking.status === "pending" || booking.status === "pendingPayment") {
      const fullRefund = Number(booking.totalPaid) || 0;
      if (isPaid && booking.paymentIntentId && fullRefund > 0) {
        await createIdempotentRefund(stripe, {
          paymentIntentId: booking.paymentIntentId,
          amountInCents: Math.round(fullRefund * 100),
          idempotencyKey: `cancel_full_refund_${bookingId}`,
        });
      }
      await bookingRef.update({
        status: "cancelled",
        escrowStatus: isPaid ? "refunded" : "cancelled",
        cancellationReason: reason || (callerIsCaregiver ? "Cancelada por el cuidador" : "Cancelada antes de aceptación"),
        escrowLock: admin.firestore.FieldValue.delete(),
      });
      lockAcquired = false;
      await Promise.all([
        reopenBookingSlots(booking.caregiverId, booking.day, booking.slot),
        syncCaregiverClientAccess(booking.clientId, booking.caregiverId),
      ]);
      return { success: true };
    }

    if (!serverIsLate) {
      const managementFee = Math.max(1.00, (Number(booking.cost) || 0) * 0.05);
      let refundAmount = (Number(booking.totalPaid) || 0) - managementFee;
      if (refundAmount < 0) refundAmount = 0;

      if (isPaid && booking.paymentIntentId && refundAmount > 0) {
        await createIdempotentRefund(stripe, {
          paymentIntentId: booking.paymentIntentId,
          amountInCents: Math.round(refundAmount * 100),
          idempotencyKey: `cancel_refund_${bookingId}`,
        });
      }
      await bookingRef.update({
        status: "cancelled",
        escrowStatus: isPaid ? "refunded" : "cancelled",
        cancellationReason: reason || "Cancelación temprana del cliente",
        escrowLock: admin.firestore.FieldValue.delete(),
      });
      lockAcquired = false;
      await Promise.all([
        reopenBookingSlots(booking.caregiverId, booking.day, booking.slot),
        syncCaregiverClientAccess(booking.clientId, booking.caregiverId),
      ]);
      return { success: true };
    }

    if (!isPaid) {
      throw new functions.https.HttpsError("failed-precondition", "El pago aún está en procesamiento bancario y no admite reparto parcial todavía.");
    }
    const refundAmount = (Number(booking.cost) || 0) * 0.45;
    if (booking.paymentIntentId && refundAmount > 0) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: Math.round(refundAmount * 100),
        idempotencyKey: `late_cancel_refund_${bookingId}`,
      });
    }
    const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
    if (caregiverDoc.data()?.stripeAccountId && (booking.paymentIntentId || booking.transferGroup)) {
      const caregiverPayout = (Number(booking.cost) || 0) * 0.45;
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
    await bookingRef.update({
      status: "cancelledLate",
      escrowStatus: "resolved_partial",
      cancellationReason: reason || "Cancelación tardía del cliente",
      escrowLock: admin.firestore.FieldValue.delete(),
    });
    lockAcquired = false;
    await Promise.all([
      reopenBookingSlots(booking.caregiverId, booking.day, booking.slot),
      syncCaregiverClientAccess(booking.clientId, booking.caregiverId),
    ]);
    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  } finally {
    if (lockAcquired) await releaseEscrowLock(bookingRef);
  }
});

exports.caregiverRejectBooking = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  const bookingId = data?.bookingId;
  if (!bookingId) throw new functions.https.HttpsError("invalid-argument", "bookingId is required.");

  const db = admin.firestore();
  const bookingRef = db.collection("bookings").doc(bookingId);
  let lockAcquired = false;

  try {
    const settledEscrowStatuses = ["released", "released_manual", "released_auto", "resolved_partial", "refunded"];
    const lockResult = await acquireEscrowLock(bookingRef, "caregiverRejectBooking", async (booking) => {
      if (booking.caregiverId !== context.auth.uid) {
        throw new functions.https.HttpsError("permission-denied", "Solo el cuidador asignado puede rechazar esta reserva.");
      }
      if (booking.status === "cancelled" || booking.status === "cancelledLate" || booking.status === "completed" || settledEscrowStatuses.includes(booking.escrowStatus)) {
        throw new functions.https.HttpsError("failed-precondition", "La reserva ya está finalizada, liquidada o cancelada.");
      }
      return {};
    });
    lockAcquired = lockResult.acquired;
    const booking = lockResult.booking;

    const isPaid = await verifyPaymentIntentIsPaid(stripe, booking);
    const refundAmount = Number(booking.totalPaid) || 0;
    if (isPaid && booking.paymentIntentId && refundAmount > 0) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: Math.round(refundAmount * 100),
        idempotencyKey: `reject_refund_${bookingId}`,
      });
    }

    await bookingRef.update({
      status: "cancelled",
      escrowStatus: isPaid ? "refunded" : "cancelled",
      cancellationReason: "Rechazada por el cuidador",
      escrowLock: admin.firestore.FieldValue.delete(),
    });
    lockAcquired = false;
    await Promise.all([
      reopenBookingSlots(booking.caregiverId, booking.day, booking.slot),
      syncCaregiverClientAccess(booking.clientId, booking.caregiverId),
    ]);

    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  } finally {
    if (lockAcquired) await releaseEscrowLock(bookingRef);
  }
});

exports.autoReleaseEscrowCron = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).pubsub.schedule('every 1 hours').onRun(async (context) => {
  const stripe = require("stripe")(stripeSecret.value());
  const db = admin.firestore();
  const now = new Date();

  // 0. Limpieza automática de bloqueos temporales (Hold System TTL: > 30 min en pendingPayment)
  try {
    const staleHolds = await db.collection("bookings").where("status", "==", "pendingPayment").get();
    for (const holdDoc of staleHolds.docs) {
      let lockAcquired = false;
      try {
        const lockRes = await acquireEscrowLock(holdDoc.ref, "cronStaleHoldCleanup", async (hb) => {
          if (hb.status !== "pendingPayment") return { skip: true };
          const createdAt = hb.createdAt ? hb.createdAt.toDate() : null;
          const ageMs = createdAt ? (now.getTime() - createdAt.getTime()) : (35 * 60 * 1000);
          if (ageMs <= 30 * 60 * 1000) return { skip: true };
          return {};
        });
        if (!lockRes.acquired) continue;
        lockAcquired = true;
        const hb = lockRes.booking;
        await reopenBookingSlots(hb.caregiverId, hb.day, hb.slot);
        await holdDoc.ref.collection("secrets").doc("checkin").delete().catch(() => {});
        await holdDoc.ref.delete();
        lockAcquired = false;
        await syncCaregiverClientAccess(hb.clientId, hb.caregiverId);
      } catch (itemErr) {
        console.error(`Cron Error cleaning pendingPayment hold ${holdDoc.id}:`, itemErr);
      } finally {
        if (lockAcquired) await releaseEscrowLock(holdDoc.ref);
      }
    }
  } catch (holdErr) {
    console.warn("Error cleaning stale pendingPayment holds:", holdErr.message);
  }
  
  // 0.5. Expiración automática de reservas en estado "pending" (no aceptadas por el cuidador a tiempo)
  try {
    const pendingSnap = await db.collection("bookings")
      .where("escrowStatus", "==", "held")
      .where("status", "==", "pending")
      .get();
    for (const pDoc of pendingSnap.docs) {
      let lockAcquired = false;
      try {
        const lockRes = await acquireEscrowLock(pDoc.ref, "cronExpirePending", async (pb) => {
          if (pb.escrowStatus !== "held" || pb.status !== "pending") return { skip: true };
          const scheduledStart = parseBookingStartDateTime(pb.day, pb.slot);
          if (!scheduledStart || now <= scheduledStart) return { skip: true };
          return {};
        });
        if (!lockRes.acquired) continue;
        lockAcquired = true;
        const pb = lockRes.booking;
        const isPaid = await verifyPaymentIntentIsPaid(stripe, pb);
        const fullRefund = Number(pb.totalPaid) || Number(pb.cost) || 0;
        if (isPaid && pb.paymentIntentId && fullRefund > 0) {
          await createIdempotentRefund(stripe, {
            paymentIntentId: pb.paymentIntentId,
            amountInCents: Math.round(fullRefund * 100),
            idempotencyKey: `expired_pending_refund_${pDoc.id}`,
          });
        }
        await reopenBookingSlots(pb.caregiverId, pb.day, pb.slot);
        await pDoc.ref.update({
          status: "cancelled",
          escrowStatus: isPaid ? "refunded" : "cancelled",
          cancellationReason: "Expirada sin respuesta del cuidador",
          escrowLock: admin.firestore.FieldValue.delete(),
        });
        lockAcquired = false;
        await syncCaregiverClientAccess(pb.clientId, pb.caregiverId);
      } catch (itemErr) {
        console.error(`Cron Error expiring pending booking ${pDoc.id}:`, itemErr);
      } finally {
        if (lockAcquired) await releaseEscrowLock(pDoc.ref);
      }
    }
  } catch (pendingErr) {
    console.warn("Error expiring unaccepted pending bookings:", pendingErr.message);
  }

  // 1. Manejo de reservas normales y No-Shows (24h tras fin teórico)
  try {
    const snapshot = await db.collection("bookings").where("escrowStatus", "==", "held").where("status", "==", "confirmed").get();
    
    for (const doc of snapshot.docs) {
      let lockAcquired = false;
      try {
        const lockRes = await acquireEscrowLock(doc.ref, "cronAutoRelease", async (b) => {
          if (b.escrowStatus !== "held" || b.status !== "confirmed") return { skip: true };
          const theoreticalStartTime = parseBookingStartDateTime(b.day, b.slot);
          const theoreticalEndTime = parseBookingEndDateTime(b.day, b.slot);
          if (!theoreticalStartTime || !theoreticalEndTime) return { skip: true };
          const payoutTime = new Date(theoreticalEndTime.getTime() + (24 * 60 * 60 * 1000));
          if (now <= payoutTime) return { skip: true };
          return {};
        });
        if (!lockRes.acquired) continue;
        lockAcquired = true;
        const b = lockRes.booking;

        const isPaid = await verifyPaymentIntentIsPaid(stripe, b);
        if (!isPaid) {
          console.log(`Skipping auto-release/refund for ${doc.id}: payment still processing or unpaid.`);
          continue;
        }

        const theoreticalStartTime = parseBookingStartDateTime(b.day, b.slot);
        const theoreticalEndTime = parseBookingEndDateTime(b.day, b.slot);

        if (!b.checkInTime) {
          // NO-SHOW: Cancelación fulminante (reembolso íntegro al cliente)
          const fullRefund = Number(b.totalPaid) || Number(b.cost) || 0;
          if (b.paymentIntentId && fullRefund > 0) {
            await createIdempotentRefund(stripe, {
              paymentIntentId: b.paymentIntentId,
              amountInCents: Math.round(fullRefund * 100),
              idempotencyKey: `noshow_refund_${doc.id}`,
            });
          }
          await doc.ref.update({
            status: "cancelledLate",
            escrowStatus: "refunded",
            cancellationReason: "No-Show",
            escrowLock: admin.firestore.FieldValue.delete(),
          });
          lockAcquired = false;
          await Promise.all([
            addIncidentToCaregiver(b.caregiverId),
            reopenBookingSlots(b.caregiverId, b.day, b.slot),
            syncCaregiverClientAccess(b.clientId, b.caregiverId),
          ]);
        } else {
          // CHECKED IN: Evaluar si llegó tarde
          const checkInDate = b.checkInTime.toDate();
          const totalTheoreticalMinutes = Math.max(1, (theoreticalEndTime.getTime() - theoreticalStartTime.getTime()) / 60000);
          const pricePerMinute = (Number(b.cost) || 0) / totalTheoreticalMinutes;
          const minutesLate = (checkInDate.getTime() - theoreticalStartTime.getTime()) / 60000;

          if (minutesLate > 15) {
            const amountToDeduct = Math.min(Number(b.cost) || 0, minutesLate * pricePerMinute);
            const newCost = Math.max(0, (Number(b.cost) || 0) - amountToDeduct);
            const newCommission = newCost * (Number(b.caregiverCommissionRate) || 0.18);
            const newPayout = newCost - newCommission;
            const amountToRefund = (Number(b.cost) || 0) - newCost;

            if (b.paymentIntentId && amountToRefund > 0) {
              await createIdempotentRefund(stripe, {
                paymentIntentId: b.paymentIntentId,
                amountInCents: Math.round(amountToRefund * 100),
                idempotencyKey: `late_checkin_refund_${doc.id}`,
              });
            }

            const caregiverDoc = await db.collection("caregivers").doc(b.caregiverId).get();
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
              paymentStatus: "paid",
              caregiverPayout: newPayout,
              caregiverCommissionAmount: newCommission,
              cost: newCost,
              escrowLock: admin.firestore.FieldValue.delete(),
            });
            lockAcquired = false;
            await Promise.all([
              addCompletedHours(b.clientId, b.caregiverId, b.slot),
              syncCaregiverClientAccess(b.clientId, b.caregiverId),
            ]);
          } else {
            const caregiverDoc = await db.collection("caregivers").doc(b.caregiverId).get();
            if (caregiverDoc.data()?.stripeAccountId && (b.paymentIntentId || b.transferGroup) && b.caregiverPayout > 0) {
              await createLinkedStripeTransfer(stripe, {
                amountInCents: Math.round(b.caregiverPayout * 100),
                destination: caregiverDoc.data().stripeAccountId,
                paymentIntentId: b.paymentIntentId,
                transferGroup: b.transferGroup,
                idempotencyKey: `auto_release_${doc.id}`,
              });
            }
            await doc.ref.update({
              status: "completed",
              escrowStatus: "released_auto",
              paymentStatus: "paid",
              escrowLock: admin.firestore.FieldValue.delete(),
            });
            lockAcquired = false;
            await Promise.all([
              addCompletedHours(b.clientId, b.caregiverId, b.slot),
              syncCaregiverClientAccess(b.clientId, b.caregiverId),
            ]);
          }
        }
      } catch (e) {
        console.error("Cron Error processing booking", doc.id, e);
      } finally {
        if (lockAcquired) await releaseEscrowLock(doc.ref);
      }
    }
  } catch (releaseCronErr) {
    console.error("Cron Error querying held confirmed bookings:", releaseCronErr.message);
  }
  
  // 2. Manejo de Disputas ignoradas por el cuidador > 24 horas
  try {
    const disputes = await db.collection("bookings")
      .where("escrowStatus", "==", "disputed")
      .where("disputeEscalated", "==", false).get();
      
    for (const doc of disputes.docs) {
      let lockAcquired = false;
      try {
        const lockRes = await acquireEscrowLock(doc.ref, "cronDisputeTimeout", async (b) => {
          if (b.escrowStatus !== "disputed" || b.disputeEscalated) return { skip: true };
          if (!b.disputeOpenedAt) return { skip: true };
          const timeoutDate = new Date(b.disputeOpenedAt.toDate().getTime() + (24 * 60 * 60 * 1000));
          if (now <= timeoutDate) return { skip: true };
          return {};
        });
        if (!lockRes.acquired) continue;
        lockAcquired = true;
        const b = lockRes.booking;

        const isPaid = await verifyPaymentIntentIsPaid(stripe, b);
        if (!isPaid) continue;
        const disputeRefund = Number(b.totalPaid) || Number(b.cost) || 0;
        if (b.paymentIntentId && disputeRefund > 0) {
          await createIdempotentRefund(stripe, {
            paymentIntentId: b.paymentIntentId,
            amountInCents: Math.round(disputeRefund * 100),
            idempotencyKey: `dispute_timeout_refund_${doc.id}`,
          });
        }
        await doc.ref.update({
          escrowStatus: "refunded",
          status: "completed",
          cancellationReason: "Disputa resuelta a favor del cliente por inactividad del cuidador",
          escrowLock: admin.firestore.FieldValue.delete(),
        });
        lockAcquired = false;
        await Promise.all([
          addIncidentToCaregiver(b.caregiverId),
          syncCaregiverClientAccess(b.clientId, b.caregiverId),
          sendPushNotification(
            b.clientId,
            "Disputa resuelta a tu favor",
            `Hemos procesado el reembolso de la reserva del ${formatDateEs(b.day)} tras 24h sin respuesta del cuidador.`,
            { type: "payment", bookingId: doc.id }
          ),
          sendPushNotification(
            b.caregiverId,
            "Disputa expirada",
            `La disputa del ${formatDateEs(b.day)} se cerró a favor del cliente por inactividad de 24h.`,
            { type: "booking", bookingId: doc.id }
          ),
        ]);
      } catch(e) {
        console.error("Error timing out dispute", doc.id, e);
      } finally {
        if (lockAcquired) await releaseEscrowLock(doc.ref);
      }
    }
  } catch (disputeQueryErr) {
    console.error("Cron Error querying active disputes:", disputeQueryErr.message);
  }
  
  // 3. Fallback: Disputas no escaladas sin disputeOpenedAt (Legacy)
  try {
    const legacyDisputes = await db.collection("bookings")
      .where("escrowStatus", "==", "disputed")
      .get();
      
    for (const doc of legacyDisputes.docs) {
      let lockAcquired = false;
      try {
        const lockRes = await acquireEscrowLock(doc.ref, "cronLegacyDispute", async (b) => {
          if (b.escrowStatus !== "disputed" || b.disputeOpenedAt || b.disputeEscalated) return { skip: true };
          const theoreticalEndTime = parseBookingEndDateTime(b.day, b.slot);
          if (!theoreticalEndTime) return { skip: true };
          const timeoutDate = new Date(theoreticalEndTime.getTime() + (72 * 60 * 60 * 1000));
          if (now <= timeoutDate) return { skip: true };
          return {};
        });
        if (!lockRes.acquired) continue;
        lockAcquired = true;
        const b = lockRes.booking;

        const isPaid = await verifyPaymentIntentIsPaid(stripe, b);
        if (!isPaid) continue;
        const legacyRefund = Number(b.totalPaid) || Number(b.cost) || 0;
        if (b.paymentIntentId && legacyRefund > 0) {
          await createIdempotentRefund(stripe, {
            paymentIntentId: b.paymentIntentId,
            amountInCents: Math.round(legacyRefund * 100),
            idempotencyKey: `legacy_dispute_refund_${doc.id}`,
          });
        }
        await doc.ref.update({
          escrowStatus: "refunded",
          status: "completed",
          cancellationReason: "Disputa resuelta por inactividad (Legacy)",
          escrowLock: admin.firestore.FieldValue.delete(),
        });
        lockAcquired = false;
        await syncCaregiverClientAccess(b.clientId, b.caregiverId);
      } catch(e) {
        console.error("Error timing out legacy dispute", doc.id, e);
      } finally {
        if (lockAcquired) await releaseEscrowLock(doc.ref);
      }
    }
  } catch (legacyQueryErr) {
    console.error("Cron Error querying legacy disputes:", legacyQueryErr.message);
  }
  
  return null;
});

exports.adminResolveDispute = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!(await isAdminCaller(context))) {
    throw new functions.https.HttpsError("permission-denied", "Solo administradores verificados.");
  }
  
  const stripe = require("stripe")(stripeSecret.value());
  const { bookingId } = data || {};
  const refundToClient = Number(data?.refundToClient || 0);
  const payoutToCaregiver = Number(data?.payoutToCaregiver || 0);
  if (!bookingId) throw new functions.https.HttpsError("invalid-argument", "bookingId requerido.");
  if (!Number.isFinite(refundToClient) || refundToClient < 0 || !Number.isFinite(payoutToCaregiver) || payoutToCaregiver < 0) {
    throw new functions.https.HttpsError("invalid-argument", "Los importes de resolución deben ser válidos y no negativos.");
  }

  const db = admin.firestore();
  const bookingRef = db.collection("bookings").doc(bookingId);
  let lockAcquired = false;

  try {
    const settledEscrowStatuses = ["released", "released_manual", "released_auto", "resolved_partial", "refunded"];
    const lockResult = await acquireEscrowLock(bookingRef, "adminResolveDispute", async (booking) => {
      if (settledEscrowStatuses.includes(booking.escrowStatus)) {
        throw new functions.https.HttpsError("failed-precondition", "Esta reserva ya fue liquidada anteriormente.");
      }
      const maxAllowed = (Number(booking.totalPaid) || Number(booking.cost) || 0) + 0.01;
      if (refundToClient + payoutToCaregiver > maxAllowed) {
        throw new functions.https.HttpsError("invalid-argument", "La suma de reembolso y pago al cuidador supera el total abonado.");
      }
      return {};
    });
    lockAcquired = lockResult.acquired;
    const booking = lockResult.booking;

    const isPaid = await verifyPaymentIntentIsPaid(stripe, booking);
    if (!isPaid && (refundToClient > 0 || payoutToCaregiver > 0)) {
      throw new functions.https.HttpsError("failed-precondition", "El PaymentIntent asociado aún no está cobrado en Stripe.");
    }
    
    if (refundToClient > 0 && booking.paymentIntentId) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: Math.round(refundToClient * 100),
        idempotencyKey: `admin_dispute_refund_${bookingId}`,
      });
    }
    
    if (payoutToCaregiver > 0) {
      const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
      if (!caregiverDoc.data()?.stripeAccountId) {
        throw new functions.https.HttpsError("failed-precondition", "El cuidador no tiene cuenta de Stripe configurada para recibir el pago.");
      }
      if (booking.paymentIntentId || booking.transferGroup) {
        await createLinkedStripeTransfer(stripe, {
          amountInCents: Math.round(payoutToCaregiver * 100),
          destination: caregiverDoc.data().stripeAccountId,
          paymentIntentId: booking.paymentIntentId,
          transferGroup: booking.transferGroup,
          idempotencyKey: `admin_dispute_transfer_${bookingId}`,
        });
      }
    }
    
    const resolvedEscrowStatus = payoutToCaregiver === 0 && refundToClient > 0 ? "refunded" : "resolved_partial";
    const remainingCommission = Math.max(0, (Number(booking.cost) || 0) - refundToClient - payoutToCaregiver);
    await bookingRef.update({
      escrowStatus: resolvedEscrowStatus,
      status: "completed",
      disputeRequested: false,
      caregiverPayout: payoutToCaregiver,
      caregiverCommissionAmount: remainingCommission,
      escrowLock: admin.firestore.FieldValue.delete(),
    });
    lockAcquired = false;
    
    if (payoutToCaregiver > 0) {
      await addCompletedHours(booking.clientId, booking.caregiverId, booking.slot);
    } else if (refundToClient > 0 && booking.caregiverId) {
      await addIncidentToCaregiver(booking.caregiverId);
    }
    await syncCaregiverClientAccess(booking.clientId, booking.caregiverId);
    
    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  } finally {
    if (lockAcquired) await releaseEscrowLock(bookingRef);
  }
});

exports.processResolutionAgreement = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const stripe = require("stripe")(stripeSecret.value());
  const bookingId = data?.bookingId;
  if (!bookingId) throw new functions.https.HttpsError("invalid-argument", "bookingId requerido.");

  const db = admin.firestore();
  const bookingRef = db.collection("bookings").doc(bookingId);
  let lockAcquired = false;

  try {
    const callerIsAdmin = await isAdminCaller(context);
    const lockResult = await acquireEscrowLock(bookingRef, "processResolutionAgreement", async (booking) => {
      if (booking.caregiverId !== context.auth.uid && !(await isFamilyAdmin(booking.clientId, context.auth.uid)) && !callerIsAdmin) {
        throw new functions.https.HttpsError("permission-denied", "No autorizado.");
      }
      if (booking.escrowStatus !== "disputed") {
        throw new functions.https.HttpsError("failed-precondition", "La reserva no tiene una disputa abierta activa.");
      }
      const proposedRefund = Number(booking.disputeAmount);
      if (!Number.isFinite(proposedRefund) || proposedRefund <= 0 || proposedRefund > (Number(booking.cost) || 0)) {
        throw new functions.https.HttpsError("failed-precondition", "El importe propuesto de disputa no es válido.");
      }
      return {};
    });
    lockAcquired = lockResult.acquired;
    const booking = lockResult.booking;
    const proposedRefund = Number(booking.disputeAmount);

    const isPaid = await verifyPaymentIntentIsPaid(stripe, booking);
    if (!isPaid) {
      throw new functions.https.HttpsError("failed-precondition", "El pago asociado aún no está liquidado en Stripe.");
    }

    const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
    if (booking.paymentIntentId && proposedRefund > 0) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: Math.round(proposedRefund * 100),
        idempotencyKey: `dispute_agree_refund_${bookingId}`,
      });
    }
    
    const dineroParaElCuidador = Math.max(0, (Number(booking.cost) || 0) - proposedRefund);
    const commissionRate = (booking.caregiverCommissionRate > 0 && booking.caregiverCommissionRate <= 0.30)
      ? booking.caregiverCommissionRate
      : 0.18;
    const comisionCuidador = dineroParaElCuidador * commissionRate;
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
          idempotencyKey: `dispute_agree_transfer_${bookingId}`,
        });
      }
    }
    
    await bookingRef.update({
      escrowStatus: "resolved_partial",
      status: "completed",
      disputeRequested: false,
      caregiverPayout: payoutCuidador,
      caregiverCommissionAmount: comisionCuidador,
      escrowLock: admin.firestore.FieldValue.delete(),
    });
    lockAcquired = false;
    await Promise.all([
      addCompletedHours(booking.clientId, booking.caregiverId, booking.slot),
      syncCaregiverClientAccess(booking.clientId, booking.caregiverId),
    ]);
    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  } finally {
    if (lockAcquired) await releaseEscrowLock(bookingRef);
  }
});

// --- FCM PUSH NOTIFICATIONS TRIGGERS ---

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");

// Función auxiliar para buscar token(s) y enviar notificación push (con soporte multifamiliar)
async function sendPushNotification(targetId, title, body, dataPayload = {}) {
  try {
    if (!targetId) return;
    const db = admin.firestore();
    const targetUids = new Set([targetId]);

    const clientSnap = await db.collection("clients").doc(targetId).get();
    if (clientSnap.exists) {
      const clientData = clientSnap.data() || {};
      if (clientData.ownerUid) targetUids.add(clientData.ownerUid);
      if (Array.isArray(clientData.memberUids)) {
        clientData.memberUids.forEach((uid) => {
          if (uid) targetUids.add(uid);
        });
      }
      if (clientData.members && typeof clientData.members === "object") {
        Object.keys(clientData.members).forEach((uid) => {
          if (uid) targetUids.add(uid);
        });
      }
    }

    const userSnaps = await Promise.all(
      [...targetUids].map((uid) => db.collection("users").doc(uid).get())
    );
    const tokens = [
      ...new Set(
        userSnaps
          .filter((doc) => doc.exists && doc.data()?.fcmToken)
          .map((doc) => doc.data().fcmToken)
      ),
    ];

    if (tokens.length === 0) {
      console.log(`Ningún destinatario de ${targetId} tiene fcmToken registrado.`);
      return;
    }

    await Promise.all(
      tokens.map((token) =>
        admin.messaging().send({
          token,
          notification: { title, body },
          data: dataPayload,
        })
      )
    );
    console.log(`Push enviada con éxito a ${tokens.length} dispositivo(s) para ${targetId}`);
  } catch (error) {
    console.error(`Error enviando push a ${targetId}:`, error);
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
  if (!caregiverId) return;
  const db = admin.firestore();
  const cgRef = db.collection("caregivers").doc(caregiverId);
  const userRef = db.collection("users").doc(caregiverId);
  const [cgDoc, userDoc] = await Promise.all([cgRef.get(), userRef.get()]);
  if (!cgDoc.exists && !userDoc.exists) return;

  const baseData = (cgDoc.exists ? cgDoc.data() : userDoc.data()) || {};
  const now = new Date();
  const incidentDates = Array.isArray(baseData.incidentDates) ? [...baseData.incidentDates] : [];
  incidentDates.push(admin.firestore.Timestamp.fromDate(now));

  const thirtyDaysAgo = new Date(now.getTime() - (30 * 24 * 60 * 60 * 1000));
  const ninetyDaysAgo = new Date(now.getTime() - (90 * 24 * 60 * 60 * 1000));
  const toJsDate = (d) => (d && typeof d.toDate === "function" ? d.toDate() : new Date(d));

  const incidents30 = incidentDates.filter((d) => toJsDate(d) > thirtyDaysAgo).length;
  const incidents90 = incidentDates.filter((d) => toJsDate(d) > ninetyDaysAgo).length;

  let blockedUntil = baseData.blockedUntil ? toJsDate(baseData.blockedUntil) : null;
  let status = baseData.status || "active";

  if (incidents90 > 10) {
    status = "suspended";
    blockedUntil = new Date(now.getTime() + (3650 * 24 * 60 * 60 * 1000)); // 10 years
  } else if (incidents30 > 3) {
    if (status !== "suspended") {
      blockedUntil = new Date(now.getTime() + (5 * 24 * 60 * 60 * 1000)); // 5 days
    }
  }

  const updateData = { incidentDates, status };
  if (blockedUntil) updateData.blockedUntil = admin.firestore.Timestamp.fromDate(blockedUntil);

  const writes = [];
  if (cgDoc.exists) writes.push(cgRef.set(updateData, { merge: true }));
  if (userDoc.exists) writes.push(userRef.set(updateData, { merge: true }));
  await Promise.all(writes);
}

// 3. Actualización de Reserva (Confirmación, Cancelación, Pagos, Estados en Vivo y Disputas) (V2)
exports.pushOnBookingUpdated = onDocumentUpdated({
  document: "bookings/{bookingId}",
  region: "europe-west1"
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (before.escrowStatus !== "disputed" && after.escrowStatus === "disputed") {
    // Notificar al cuidador de la disputa (sin penalizar hasta resolución confirmada en contra)
    await sendPushNotification(
      after.caregiverId,
      "Disputa Abierta",
      `El cliente ha abierto una disputa proponiendo un reembolso de ${after.disputeAmount}€. Tienes 24 horas para responder.`,
      { type: "booking", bookingId: event.params.bookingId }
    );
  }

  if (before.liveStatus !== "on_the_way" && after.liveStatus === "on_the_way") {
    await sendPushNotification(
      after.clientId,
      "Cuidador en camino",
      `${after.caregiverName || "Tu cuidador/a"} va de camino al servicio del ${formatDateEs(after.day)}.`,
      { type: "tracking", bookingId: event.params.bookingId }
    );
  }

  if (!before.checkInTime && after.checkInTime) {
    await sendPushNotification(
      after.clientId,
      "Servicio iniciado",
      `${after.caregiverName || "Tu cuidador/a"} ha registrado su llegada en el domicilio.`,
      { type: "tracking", bookingId: event.params.bookingId }
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
    } else if (after.status === "completed") {
      await sendPushNotification(
        after.clientId,
        "Servicio completado",
        `El servicio del ${formatDateEs(after.day)} ha finalizado. Ya puedes valorar a ${after.caregiverName || "tu cuidador/a"}.`,
        { type: "booking", bookingId: event.params.bookingId }
      );
    }
  }
  return null;
});

exports.pushOnCaregiverVerificationUpdated = onDocumentUpdated({
  document: "caregivers/{caregiverId}",
  region: "europe-west1"
}, async (event) => {
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};
  if (before.verificationStatus === after.verificationStatus) return null;

  if (after.verificationStatus === "approved") {
    await sendPushNotification(
      event.params.caregiverId,
      "¡Perfil Verificado!",
      "Tu documentación ha sido aprobada. Ya eres visible para las familias en SeniCare.",
      { type: "verification", caregiverId: event.params.caregiverId }
    );
  } else if (after.verificationStatus === "rejected") {
    await sendPushNotification(
      event.params.caregiverId,
      "Documentación rechazada",
      after.verificationRejectionReason || "Revisa y vuelve a subir tu DNI o certificado de antecedentes desde Verificación.",
      { type: "verification", caregiverId: event.params.caregiverId }
    );
  }
  return null;
});

async function applyTipSettlement(stripe, paymentIntent) {
  const bookingId = paymentIntent?.metadata?.bookingId;
  if (!bookingId) return;
  const amountEur = Math.max(0, (paymentIntent.amount_received || paymentIntent.amount || 0) / 100);
  if (amountEur <= 0) return;

  const db = admin.firestore();
  const bookingRef = db.collection("bookings").doc(bookingId);
  let caregiverId = null;

  const shouldTransfer = await db.runTransaction(async (tx) => {
    const snap = await tx.get(bookingRef);
    if (!snap.exists) return false;
    const b = snap.data() || {};
    caregiverId = b.caregiverId;
    const processed = Array.isArray(b.processedTipPaymentIntents) ? b.processedTipPaymentIntents : [];
    if (processed.includes(paymentIntent.id)) return false;

    tx.update(bookingRef, {
      tipAmount: admin.firestore.FieldValue.increment(amountEur),
      processedTipPaymentIntents: admin.firestore.FieldValue.arrayUnion(paymentIntent.id),
    });
    return true;
  });

  if (shouldTransfer && caregiverId) {
    const cgDoc = await db.collection("caregivers").doc(caregiverId).get();
    const dest = cgDoc.data()?.stripeAccountId;
    if (dest) {
      await createLinkedStripeTransfer(stripe, {
        amountInCents: Math.round(amountEur * 100),
        destination: dest,
        paymentIntentId: paymentIntent.id,
        transferGroup: paymentIntent.transfer_group || undefined,
        idempotencyKey: `tip_transfer_${paymentIntent.id}`,
      });
    }
    await sendPushNotification(
      caregiverId,
      "¡Has recibido una propina!",
      `La familia te ha enviado ${amountEur.toFixed(2)}€ de propina íntegra por tu servicio.`,
      { type: "payment", bookingId }
    );
  }
}

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

    const db = admin.firestore();
    const eventRef = db.collection("webhook_events").doc(event.id);
    const eventSnap = await eventRef.get();
    if (eventSnap.exists) {
      return res.json({ received: true, duplicate: true });
    }
  
    if (event.type === "payment_intent.succeeded") {
      const rawIntent = event.data.object;
      if (String(rawIntent.currency || "").toLowerCase() !== "eur") {
        console.warn(`Ignored non-EUR PaymentIntent ${rawIntent.id}: ${rawIntent.currency}`);
        await eventRef.set({ type: event.type, ignored: "non_eur", processedAt: admin.firestore.FieldValue.serverTimestamp() });
        return res.json({ received: true });
      }
      let expandedIntent = rawIntent;
      let resolvedMethodType = extractStripePaymentMethodType(rawIntent);
      try {
        expandedIntent = await stripe.paymentIntents.retrieve(rawIntent.id, {
          expand: ["latest_charge"],
        });
        resolvedMethodType = extractStripePaymentMethodType(expandedIntent);
      } catch (_) {}

      if (rawIntent.metadata?.type === "tip") {
        try {
          await applyTipSettlement(stripe, expandedIntent);
          await eventRef.set({ type: event.type, processedAt: admin.firestore.FieldValue.serverTimestamp() });
          return res.json({ received: true });
        } catch (tipErr) {
          console.error("Error settling tip via webhook:", tipErr);
          return res.status(500).send("Tip Settlement Error");
        }
      }

      try {
        let docs = (await db.collection("bookings").where("paymentIntentId", "==", rawIntent.id).get()).docs;
        if (docs.length === 0 && typeof rawIntent.metadata?.bookingIds === "string" && rawIntent.metadata.bookingIds.trim()) {
          const metaIds = rawIntent.metadata.bookingIds.split(",").map((s) => s.trim()).filter(Boolean);
          const fetched = await Promise.all(metaIds.map((id) => db.collection("bookings").doc(id).get()));
          docs = fetched.filter((d) => d.exists);
        }

        const batch = db.batch();
        let totalCalculatedPaid = 0;
        let updatedCount = 0;
        
        for (const doc of docs) {
          const booking = doc.data();
          if (booking.paymentIntentId && booking.paymentIntentId !== rawIntent.id) {
            continue;
          }
          if (rawIntent.metadata?.familyId && booking.clientId && rawIntent.metadata.familyId !== booking.clientId) {
            continue;
          }
          const trueCost = Number(booking.cost) || 0;
          const rawFeeRate = Number(booking.clientFeeRate);
          const expectedFeeRate = (Number.isFinite(rawFeeRate) && rawFeeRate >= STANDARD_CLIENT_FEE_RATE && rawFeeRate <= 0.15)
            ? rawFeeRate
            : STANDARD_CLIENT_FEE_RATE;

          const trueClientFee = Math.round(trueCost * expectedFeeRate * 100) / 100;
          const trueTotalPaid = Math.round((trueCost + trueClientFee) * 100) / 100;
          const rawCommRate = Number(booking.caregiverCommissionRate);
          const commissionRate = (Number.isFinite(rawCommRate) && rawCommRate >= 0.05 && rawCommRate <= 0.25)
            ? rawCommRate
            : 0.18;
          const trueCommissionAmount = Math.round(trueCost * commissionRate * 100) / 100;
          const truePayout = Math.round((trueCost - trueCommissionAmount) * 100) / 100;
          
          totalCalculatedPaid += trueTotalPaid;
          
          const isOfferBooking = Boolean(booking.offerId || booking.isJobOffer);
          const newStatus = (booking.status === "confirmed" || isOfferBooking) ? "confirmed" : (booking.status === "pendingPayment" ? "pending" : booking.status);
          const nextEscrow = (!booking.escrowStatus || booking.escrowStatus === "none") ? "held" : booking.escrowStatus;

          batch.update(doc.ref, {
            status: newStatus,
            paymentStatus: "paid",
            escrowStatus: nextEscrow,
            paymentIntentId: rawIntent.id,
            paymentMethodType: resolvedMethodType,
            clientFee: trueClientFee,
            caregiverCommissionAmount: trueCommissionAmount,
            caregiverPayout: truePayout,
            totalPaid: trueTotalPaid
          });
          updatedCount++;
        }
        
        const expectedCents = Math.round(totalCalculatedPaid * 100);
        const toleranceCents = Math.max(2, updatedCount * 2);
        if (updatedCount > 0 && rawIntent.amount < (expectedCents - toleranceCents)) {
            console.error(`Fraud detected: Paid ${rawIntent.amount} but expected ${expectedCents}.`);
            await eventRef.set({ type: event.type, rejected: "insufficient_amount", processedAt: admin.firestore.FieldValue.serverTimestamp() });
            return res.status(200).send("Payment amount insufficient, bookings not confirmed.");
        }
        
        if (updatedCount > 0) {
          await batch.commit();
        }
        await eventRef.set({ type: event.type, updatedCount, processedAt: admin.firestore.FieldValue.serverTimestamp() });
        console.log(`Updated and sanitized ${updatedCount} bookings for PaymentIntent ${rawIntent.id} (${resolvedMethodType})`);
      } catch (e) {
        console.error("Error updating bookings:", e);
        return res.status(500).send("Internal Server Error");
      }
    } else if (event.type === "payment_intent.processing") {
      const rawIntent = event.data.object;
      if (String(rawIntent.currency || "").toLowerCase() !== "eur") {
        return res.json({ received: true });
      }
      try {
        const snap = await db.collection("bookings")
          .where("paymentIntentId", "==", rawIntent.id).get();
        const batch = db.batch();
        for (const doc of snap.docs) {
          const b = doc.data();
          const isOfferBooking = Boolean(b.offerId || b.isJobOffer);
          batch.update(doc.ref, {
            status: b.status === "pendingPayment" ? (isOfferBooking ? "confirmed" : "pending") : b.status,
            escrowStatus: (!b.escrowStatus || b.escrowStatus === "none") ? "held" : b.escrowStatus,
            paymentStatus: "processing",
            paymentMethodType: extractStripePaymentMethodType(rawIntent),
          });
        }
        await batch.commit();
        await eventRef.set({ type: event.type, processedAt: admin.firestore.FieldValue.serverTimestamp() });
      } catch (e) {
        console.error("Error marking processing booking:", e);
      }
    } else if (event.type === "payment_intent.payment_failed") {
      const rawIntent = event.data.object;
      try {
        const snap = await db.collection("bookings")
          .where("paymentIntentId", "==", rawIntent.id).get();
        const batch = db.batch();
        for (const doc of snap.docs) {
          const status = doc.data()?.status;
          if (status === "pendingPayment" || status === "pending") {
            batch.update(doc.ref, { paymentStatus: "failed" });
          }
        }
        await batch.commit();
        await eventRef.set({ type: event.type, processedAt: admin.firestore.FieldValue.serverTimestamp() });
      } catch (e) {
        console.error("Error marking failed payment:", e);
      }
    } else if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      const piId = typeof session.payment_intent === "string"
        ? session.payment_intent
        : session.payment_intent?.id;
      const rawIds = session.metadata?.bookingIds;
      const sessionCurrency = String(session.currency || "eur").toLowerCase();
      if (sessionCurrency === "eur" && piId && typeof rawIds === "string" && rawIds.trim()) {
        try {
          const ids = rawIds.split(",").map((s) => s.trim()).filter(Boolean);
          const isPaidNow = session.payment_status === "paid" || session.payment_status === "no_payment_required";
          const batch = db.batch();
          let updatedCount = 0;
          for (const id of ids) {
            const ref = db.collection("bookings").doc(id);
            const snap = await ref.get();
            if (!snap.exists) continue;
            const b = snap.data() || {};
            if (b.paymentIntentId && b.paymentIntentId !== piId) continue;
            if (session.metadata?.familyId && b.clientId && session.metadata.familyId !== b.clientId) continue;
            const isOfferBooking = Boolean(b.offerId || b.isJobOffer);
            batch.set(
              ref,
              {
                paymentIntentId: piId,
                paymentStatus: isPaidNow ? "paid" : "processing",
                status: b.status === "pendingPayment" ? (isOfferBooking ? "confirmed" : "pending") : b.status,
                escrowStatus: (!b.escrowStatus || b.escrowStatus === "none") ? "held" : b.escrowStatus,
              },
              { merge: true }
            );
            updatedCount++;
          }
          if (updatedCount > 0) await batch.commit();
          await eventRef.set({ type: event.type, updatedCount, processedAt: admin.firestore.FieldValue.serverTimestamp() });
        } catch (e) {
          console.error("Error linking checkout session bookings:", e);
        }
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
  if (!(await isAdminCaller(context))) throw new functions.https.HttpsError("permission-denied", "Solo administradores verificados.");
  const { caregiverId, days } = data;
  if (!caregiverId) throw new functions.https.HttpsError("invalid-argument", "caregiverId requerido.");
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
  
  const db = admin.firestore();
  const cgRef = db.collection("caregivers").doc(caregiverId);
  const userRef = db.collection("users").doc(caregiverId);
  const [cgSnap, userSnap] = await Promise.all([cgRef.get(), userRef.get()]);
  const writes = [];
  if (cgSnap.exists) writes.push(cgRef.set(updateData, { merge: true }));
  if (userSnap.exists) writes.push(userRef.set(updateData, { merge: true }));
  if (writes.length === 0) {
    throw new functions.https.HttpsError("not-found", "Cuidador no encontrado.");
  }
  await Promise.all(writes);
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

const INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function generateInviteCode(length = 8) {
  let code = "";
  for (let i = 0; i < length; i++) {
    code += INVITE_ALPHABET[crypto.randomInt(0, INVITE_ALPHABET.length)];
  }
  return code;
}

exports.createFamilyInvite = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  await checkRateLimit(`invite_create:${uid}`, 15, 60 * 60 * 1000);
  const db = admin.firestore();
  const familyId = (typeof data.familyId === "string" && data.familyId.trim()) ? data.familyId.trim() : uid;

  if (!(await isFamilyAdmin(familyId, uid))) {
    throw new functions.https.HttpsError("permission-denied", "Solo un Administrador familiar puede generar invitaciones.");
  }

  const role = data.role === "admin" ? "admin" : "collaborator";
  const maxUses = Math.min(Math.max(Number(data.maxUses) || 5, 1), 20);
  const validHours = Math.min(Math.max(Number(data.validHours) || 168, 1), 720);
  const clientSnap = await db.collection("clients").doc(familyId).get();
  const clientData = clientSnap.data() || {};
  const familyName = (typeof data.familyName === "string" && data.familyName.trim())
    ? data.familyName.trim()
    : (clientData.name || "Familia SeniCare");

  let code = generateInviteCode();
  for (let attempt = 0; attempt < 5; attempt++) {
    const existing = await db.collection("family_invites").doc(code).get();
    if (!existing.exists) break;
    code = generateInviteCode();
  }

  const now = new Date();
  const expiresAt = new Date(now.getTime() + validHours * 3600 * 1000);
  const payload = {
    code,
    familyId,
    familyName,
    role,
    createdByUid: uid,
    createdAt: now.toISOString(),
    expiresAt: expiresAt.toISOString(),
    maxUses,
    usedCount: 0,
    revoked: false,
  };
  if (typeof data.invitedEmail === "string" && data.invitedEmail.trim()) {
    payload.invitedEmail = data.invitedEmail.trim().toLowerCase();
  }

  await db.collection("family_invites").doc(code).set(payload);
  return payload;
});

exports.revokeFamilyInvite = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const db = admin.firestore();
  const code = String(data.code || "").trim().toUpperCase();
  if (!code) throw new functions.https.HttpsError("invalid-argument", "Código requerido.");

  const ref = db.collection("family_invites").doc(code);
  const snap = await ref.get();
  if (!snap.exists) return { success: true };

  const invite = snap.data() || {};
  if (!(await isFamilyAdmin(invite.familyId, uid))) {
    throw new functions.https.HttpsError("permission-denied", "Solo un Administrador familiar puede revocar esta invitación.");
  }

  await ref.update({ revoked: true, revokedAt: admin.firestore.FieldValue.serverTimestamp() });
  return { success: true };
});

async function attachMemberTransaction(tx, db, { familyId, uid, email, displayName, role, joinedVia, consumeInvitedEmail }) {
  const familyRef = db.collection("clients").doc(familyId);
  const familySnap = await tx.get(familyRef);
  if (!familySnap.exists) {
    throw new functions.https.HttpsError("not-found", "Cuenta familiar no encontrada.");
  }
  const fData = familySnap.data() || {};
  const ownerUid = fData.ownerUid || familyId;
  const currentMembers = { ...(fData.members || {}) };
  if (!currentMembers[ownerUid]) {
    currentMembers[ownerUid] = {
      uid: ownerUid,
      email: "",
      displayName: fData.name || "Administrador",
      role: "admin",
      joinedVia: "owner",
      isOwner: true,
    };
  }

  const alreadyMember = Boolean(
    uid === ownerUid ||
    (Array.isArray(fData.memberUids) && fData.memberUids.includes(uid)) ||
    currentMembers[uid]
  );

  const effectiveRole = uid === ownerUid ? "admin" : (alreadyMember && currentMembers[uid]?.role ? currentMembers[uid].role : role);
  if (!alreadyMember) {
    currentMembers[uid] = {
      uid,
      email: email || "",
      displayName: (displayName || "").trim() || (email ? email.split("@")[0] : "Familiar"),
      role: effectiveRole,
      joinedAt: new Date().toISOString(),
      joinedVia,
      isOwner: false,
    };
  }

  const nextMemberUids = [...new Set([ownerUid, ...(fData.memberUids || []), uid].filter(Boolean))];
  const nextAuthorizedEmails = Array.isArray(fData.authorizedFamilyEmails)
    ? fData.authorizedFamilyEmails.filter((e) => !consumeInvitedEmail || String(e).trim().toLowerCase() !== consumeInvitedEmail)
    : [];
  const nextEmailRoles = { ...(fData.familyEmailRoles || {}) };
  if (consumeInvitedEmail) {
    delete nextEmailRoles[consumeInvitedEmail];
  }

  tx.set(familyRef, {
    ownerUid,
    memberUids: nextMemberUids,
    members: currentMembers,
    authorizedFamilyEmails: nextAuthorizedEmails,
    familyEmailRoles: nextEmailRoles,
  }, { merge: true });

  tx.set(db.collection("users").doc(uid), {
    activeFamilyId: familyId,
    role: "client",
  }, { merge: true });

  return {
    familyId,
    familyName: fData.name || "Familia SeniCare",
    role: effectiveRole,
    alreadyMember,
  };
}

exports.joinFamilyByCode = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  await checkRateLimit(`invite_join:${uid}`, 8, 10 * 60 * 1000);
  const db = admin.firestore();
  const code = String(data.code || "").replace(/[\s\-_]/g, "").toUpperCase();
  if (!code) throw new functions.https.HttpsError("invalid-argument", "Código de invitación inválido.");

  const inviteRef = db.collection("family_invites").doc(code);
  const result = await db.runTransaction(async (tx) => {
    const inviteSnap = await tx.get(inviteRef);
    if (!inviteSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Código de invitación no encontrado.");
    }
    const invite = inviteSnap.data() || {};
    if (invite.revoked) {
      throw new functions.https.HttpsError("failed-precondition", "Esta invitación ha sido revocada.");
    }
    if (invite.expiresAt && new Date(invite.expiresAt).getTime() < Date.now()) {
      throw new functions.https.HttpsError("deadline-exceeded", "Esta invitación ha caducado.");
    }
    if ((invite.usedCount || 0) >= (invite.maxUses || 5)) {
      throw new functions.https.HttpsError("resource-exhausted", "Esta invitación ha alcanzado el límite de usos.");
    }

    const joined = await attachMemberTransaction(tx, db, {
      familyId: invite.familyId,
      uid,
      email: context.auth.token.email || "",
      displayName: data.displayName || context.auth.token.name || "",
      role: invite.role === "admin" ? "admin" : "collaborator",
      joinedVia: "code",
    });

    if (!joined.alreadyMember) {
      tx.update(inviteRef, { usedCount: admin.firestore.FieldValue.increment(1) });
    }
    return joined;
  });

  if (!result.alreadyMember) {
    await sendPushNotification(
      result.familyId,
      "Nuevo familiar conectado",
      `${(data.displayName || context.auth.token.name || context.auth.token.email || "Un familiar")} se ha unido como ${result.role === "admin" ? "Administrador" : "Familiar colaborador"}.`,
      { type: "family_member_joined", familyId: result.familyId }
    );
  }
  await mergeUserClaims(uid, { familyId: result.familyId });
  return result;
});

exports.claimPendingFamilyInvite = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const email = (context.auth.token.email || "").trim().toLowerCase();
  const emailVerified = context.auth.token.email_verified === true;

  if (!email || !emailVerified) {
    return { familyId: null, reason: "unverified_email" };
  }

  const db = admin.firestore();
  const matchingFamilies = await db
    .collection("clients")
    .where("authorizedFamilyEmails", "array-contains", email)
    .limit(1)
    .get();

  if (matchingFamilies.empty) {
    return { familyId: null };
  }

  const targetDoc = matchingFamilies.docs[0];
  const fData = targetDoc.data() || {};
  const configuredRole = (fData.familyEmailRoles && fData.familyEmailRoles[email]) || "collaborator";

  const result = await db.runTransaction(async (tx) => {
    return attachMemberTransaction(tx, db, {
      familyId: targetDoc.id,
      uid,
      email,
      displayName: data.displayName || context.auth.token.name || "",
      role: configuredRole === "admin" ? "admin" : "collaborator",
      joinedVia: "email",
      consumeInvitedEmail: email,
    });
  });

  if (!result.alreadyMember) {
    await sendPushNotification(
      result.familyId,
      "Familiar conectado por email",
      `${email} se ha unido automáticamente a la cuenta familiar.`,
      { type: "family_member_joined", familyId: result.familyId }
    );
  }
  await mergeUserClaims(uid, { familyId: result.familyId });
  return result;
});

exports.updateFamilyMemberRole = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const { familyId, memberUid, role } = data;
  if (!familyId || !memberUid) throw new functions.https.HttpsError("invalid-argument", "Datos incompletos.");
  if (!(await isFamilyAdmin(familyId, uid))) {
    throw new functions.https.HttpsError("permission-denied", "Solo un Administrador familiar puede cambiar roles.");
  }

  const db = admin.firestore();
  const nextRole = role === "admin" ? "admin" : "collaborator";
  await db.runTransaction(async (tx) => {
    const ref = db.collection("clients").doc(familyId);
    const snap = await tx.get(ref);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Familia no encontrada.");
    const fData = snap.data() || {};
    const ownerUid = fData.ownerUid || familyId;
    if (memberUid === ownerUid && nextRole !== "admin") {
      throw new functions.https.HttpsError("failed-precondition", "El propietario debe mantenerse como Administrador.");
    }
    tx.update(ref, { [`members.${memberUid}.role`]: nextRole });
  });

  return { success: true, role: nextRole };
});

exports.removeFamilyMember = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const { familyId, memberUid } = data;
  if (!familyId || !memberUid) throw new functions.https.HttpsError("invalid-argument", "Datos incompletos.");

  const isSelfLeaving = uid === memberUid;
  if (!isSelfLeaving && !(await isFamilyAdmin(familyId, uid))) {
    throw new functions.https.HttpsError("permission-denied", "No tienes permisos para desconectar a este familiar.");
  }

  const db = admin.firestore();
  await db.runTransaction(async (tx) => {
    const ref = db.collection("clients").doc(familyId);
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const fData = snap.data() || {};
    const ownerUid = fData.ownerUid || familyId;
    if (memberUid === ownerUid) {
      throw new functions.https.HttpsError("failed-precondition", "El propietario principal no puede desconectarse sin eliminar la cuenta.");
    }
    tx.update(ref, {
      memberUids: admin.firestore.FieldValue.arrayRemove(memberUid),
      [`members.${memberUid}`]: admin.firestore.FieldValue.delete(),
    });
    const userRef = db.collection("users").doc(memberUid);
    const userSnap = await tx.get(userRef);
    if (userSnap.exists && userSnap.data()?.activeFamilyId === familyId) {
      tx.update(userRef, { activeFamilyId: admin.firestore.FieldValue.delete() });
    }
  });

  await mergeUserClaims(memberUid, { familyId: null });
  return { success: true };
});

async function deleteCollectionDocs(colRef, batchSize = 200) {
  let snap = await colRef.limit(batchSize).get();
  while (!snap.empty) {
    const batch = colRef.firestore.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    if (snap.size < batchSize) break;
    snap = await colRef.limit(batchSize).get();
  }
}

function serializeFirestoreValue(val) {
  if (val === null || val === undefined) return val;
  if (typeof val.toDate === "function") return val.toDate().toISOString();
  if (Array.isArray(val)) return val.map(serializeFirestoreValue);
  if (typeof val === "object") {
    const out = {};
    for (const [k, v] of Object.entries(val)) {
      if (k === "checkInPinHash" || k === "escrowLock") continue;
      out[k] = serializeFirestoreValue(v);
    }
    return out;
  }
  return val;
}

exports.exportUserDataRgpd = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const db = admin.firestore();
  const [userSnap, caregiverSnap, ownClientSnap, clientBookings, cgBookings, notificationsSnap] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("caregivers").doc(uid).get(),
    db.collection("clients").doc(uid).get(),
    db.collection("bookings").where("clientId", "==", uid).limit(250).get(),
    db.collection("bookings").where("caregiverId", "==", uid).limit(250).get(),
    db.collection("users").doc(uid).collection("notifications").limit(100).get(),
  ]);

  return {
    exportedAt: new Date().toISOString(),
    schemaVersion: "1.0",
    uid,
    email: context.auth.token?.email || null,
    user: userSnap.exists ? serializeFirestoreValue(userSnap.data()) : null,
    caregiverProfile: caregiverSnap.exists ? serializeFirestoreValue(caregiverSnap.data()) : null,
    clientProfile: ownClientSnap.exists ? serializeFirestoreValue(ownClientSnap.data()) : null,
    bookingsAsClient: clientBookings.docs.map((d) => ({ id: d.id, ...serializeFirestoreValue(d.data()) })),
    bookingsAsCaregiver: cgBookings.docs.map((d) => ({ id: d.id, ...serializeFirestoreValue(d.data()) })),
    notifications: notificationsSnap.docs.map((d) => ({ id: d.id, ...serializeFirestoreValue(d.data()) })),
  };
});

exports.deleteUserAccountRgpd = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const db = admin.firestore();
  try {
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    const activeFamilyId = userSnap.data()?.activeFamilyId;

    await Promise.all([
      deleteCollectionDocs(db.collection("caregivers").doc(uid).collection("private")),
      deleteCollectionDocs(db.collection("caregivers").doc(uid).collection("availability")),
      deleteCollectionDocs(db.collection("users").doc(uid).collection("notifications")),
      deleteCollectionDocs(db.collection("clients").doc(uid).collection("invites")),
    ]);

    try {
      const bucket = admin.storage().bucket();
      const prefixes = [
        `caregiver_docs/${uid}/`,
        `caregiver_avatars/${uid}/`,
        `caregiver_voice/${uid}/`,
      ];
      await Promise.all(
        prefixes.map((prefix) =>
          bucket.deleteFiles({ prefix }).catch((e) => {
            console.warn(`Storage purge warning (${prefix}):`, e.message);
          })
        )
      );
    } catch (storageErr) {
      console.warn("Storage bucket purge skipped:", storageErr.message);
    }

    const batch = db.batch();
    if (activeFamilyId && activeFamilyId !== uid) {
      batch.set(
        db.collection("clients").doc(activeFamilyId),
        {
          memberUids: admin.firestore.FieldValue.arrayRemove(uid),
          [`members.${uid}`]: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );
    }

    const ownClientSnap = await db.collection("clients").doc(uid).get();
    if (ownClientSnap.exists) {
      const ownData = ownClientSnap.data() || {};
      const otherMembers = (ownData.memberUids || []).filter((m) => m && m !== uid);
      if (otherMembers.length === 0) {
        batch.delete(db.collection("clients").doc(uid));
      } else {
        const nextOwner = otherMembers[0];
        batch.set(
          db.collection("clients").doc(uid),
          {
            ownerUid: nextOwner,
            memberUids: admin.firestore.FieldValue.arrayRemove(uid),
            [`members.${uid}`]: admin.firestore.FieldValue.delete(),
            [`members.${nextOwner}.role`]: "admin",
            [`members.${nextOwner}.isOwner`]: true,
          },
          { merge: true }
        );
      }
    }

    batch.delete(userRef);
    batch.delete(db.collection("caregivers").doc(uid));
    await batch.commit();

    // Eliminar cuenta de Firebase Auth desde servidor para evitar estado huérfano si requiere reautenticación en cliente
    try {
      await admin.auth().deleteUser(uid);
    } catch (authErr) {
      if (authErr?.code !== "auth/user-not-found") {
        throw authErr;
      }
    }
    return { success: true };
  } catch (error) {
    console.error("Error in deleteUserAccountRgpd:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// =========================================================================
// ALTERNATIVE CHECKOUT (BIZUM / REDIRECT WALLETS) & STATUS VERIFICATION
// =========================================================================

exports.createAlternativeCheckoutSession = functions
  .region("europe-west1")
  .runWith({ secrets: [stripeSecret] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
    }
    const uid = context.auth.uid;
    await checkRateLimit(`checkout:${uid}`, 12, 10 * 60 * 1000);

    const familyId =
      typeof data?.familyId === "string" && data.familyId.trim()
        ? data.familyId.trim()
        : uid;
    if (!(await isFamilyAdmin(familyId, uid)) && !(await isAdminCaller(context))) {
      throw new functions.https.HttpsError("permission-denied", "Solo un Administrador familiar puede iniciar el pago.");
    }

    const bookingIds = Array.isArray(data?.bookingIds)
      ? data.bookingIds.map((b) => String(b).trim()).filter(Boolean)
      : [];
    if (bookingIds.length === 0) {
      throw new functions.https.HttpsError("failed-precondition", "Usa createSecureBooking con reservas registradas en el servidor.");
    }

    const db = admin.firestore();
    const docs = await Promise.all(bookingIds.map((id) => db.collection("bookings").doc(id).get()));
    let computedTotalEur = 0;
    let transferGroup = `booking_${Date.now()}`;
    let caregiverId = "";
    for (const snap of docs) {
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
      }
      const b = snap.data() || {};
      if (b.clientId !== familyId) {
        throw new functions.https.HttpsError("permission-denied", "La reserva no pertenece a esta familia.");
      }
      if (b.paymentStatus === "paid") {
        throw new functions.https.HttpsError("failed-precondition", "La reserva ya ha sido pagada.");
      }
      computedTotalEur += Number(b.totalPaid) || ((Number(b.cost) || 0) * (1 + (Number(b.clientFeeRate) || STANDARD_CLIENT_FEE_RATE)));
      if (b.transferGroup) transferGroup = b.transferGroup;
      if (b.caregiverId) caregiverId = b.caregiverId;
    }

    const amountInCents = Math.round(computedTotalEur * 100);
    if (!Number.isFinite(amountInCents) || amountInCents < 50) {
      throw new functions.https.HttpsError("invalid-argument", "El importe mínimo para este pago es 0,50 €.");
    }

    const stripe = require("stripe")(stripeSecret.value());
    const preferredMethod = String(data?.preferredMethod || "bizum").toLowerCase().trim();
    const title =
      typeof data?.title === "string" && data.title.trim()
        ? data.title.trim().slice(0, 120)
        : "Servicio asistencial SeniCare";
    const bookingIdsStr = bookingIds.join(",").slice(0, 450);

    const projectId = process.env.GCLOUD_PROJECT || "senicare-3342d";
    const returnBaseUrl = `https://europe-west1-${projectId}.cloudfunctions.net/stripeCheckoutRedirect`;
    const customerInfo = await getOrCreateStripeCustomerAndSession(stripe, context.auth);

    const sessionBase = {
      mode: "payment",
      locale: "es",
      customer: customerInfo.customerId || undefined,
      line_items: [
        {
          price_data: {
            currency: "eur",
            product_data: {
              name: title,
              description: "Pago protegido en custodia bancaria (Stripe Escrow) · SeniCare",
            },
            unit_amount: amountInCents,
          },
          quantity: 1,
        },
      ],
      payment_intent_data: {
        transfer_group: transferGroup,
        metadata: {
          familyId,
          paidByUid: uid,
          caregiverId,
          preferredMethod,
          bookingIds: bookingIdsStr,
        },
      },
      metadata: {
        familyId,
        paidByUid: uid,
        caregiverId,
        preferredMethod,
        bookingIds: bookingIdsStr,
      },
      success_url: `${returnBaseUrl}?status=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${returnBaseUrl}?status=cancelled&session_id={CHECKOUT_SESSION_ID}`,
    };

    let session;
    let fallbackUsed = false;
    try {
      const methodList = PAYMENT_PREFERENCE_METHOD_TYPES[preferredMethod];
      session = await stripe.checkout.sessions.create({
        ...sessionBase,
        ...(methodList ? { payment_method_types: methodList } : {}),
      });
    } catch (explicitErr) {
      console.warn(
        `Checkout Session '${preferredMethod}' fallback to Dashboard dynamic methods:`,
        explicitErr.message
      );
      fallbackUsed = true;
      session = await stripe.checkout.sessions.create(sessionBase);
    }

    const piId = typeof session.payment_intent === "string"
      ? session.payment_intent
      : session.payment_intent?.id || null;
    if (piId) {
      const batch = db.batch();
      for (const snap of docs) {
        batch.update(snap.ref, { paymentIntentId: piId });
      }
      await batch.commit();
    }

    return {
      sessionId: session.id,
      url: session.url,
      transferGroup,
      paymentIntentId: piId,
      requestedMethod: preferredMethod,
      fallbackUsed,
    };
  });

exports.verifyStripePaymentStatus = functions
  .region("europe-west1")
  .runWith({ secrets: [stripeSecret] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
    }
    const uid = context.auth.uid;
    await checkRateLimit(`verify_pay:${uid}`, 30, 10 * 60 * 1000);

    const stripe = require("stripe")(stripeSecret.value());
    const sessionId = typeof data?.sessionId === "string" ? data.sessionId.trim() : "";
    const paymentIntentId = typeof data?.paymentIntentId === "string" ? data.paymentIntentId.trim() : "";

    let paymentIntent = null;
    let session = null;
    let sessionStatus = null;
    let paymentStatus = null;

    if (sessionId) {
      session = await stripe.checkout.sessions.retrieve(sessionId, {
        expand: ["payment_intent.latest_charge"],
      });
      sessionStatus = session.status;
      paymentStatus = session.payment_status;
      if (session.payment_intent && typeof session.payment_intent === "object") {
        paymentIntent = session.payment_intent;
      }
    } else if (paymentIntentId) {
      paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId, {
        expand: ["latest_charge"],
      });
    } else {
      throw new functions.https.HttpsError("invalid-argument", "Falta sessionId o paymentIntentId.");
    }

    const meta = (session?.metadata && Object.keys(session.metadata).length > 0)
      ? session.metadata
      : (paymentIntent?.metadata || {});
    const metaFamilyId = String(meta.familyId || "").trim();
    const metaPaidByUid = String(meta.paidByUid || "").trim();
    const callerIsAdmin = await isAdminCaller(context);
    const authorized = callerIsAdmin ||
      (metaPaidByUid && metaPaidByUid === uid) ||
      (metaFamilyId && (await isFamilyMember(metaFamilyId, uid)));
    if (!authorized) {
      throw new functions.https.HttpsError("permission-denied", "No tienes permiso para consultar este estado de pago.");
    }

    const piStatus = paymentIntent?.status || (paymentStatus === "paid" ? "succeeded" : "requires_payment_method");
    return {
      status: piStatus,
      isPaid: piStatus === "succeeded" || paymentStatus === "paid",
      isProcessing: piStatus === "processing",
      sessionStatus,
      paymentIntentId: paymentIntent?.id || null,
      paymentMethodType: extractStripePaymentMethodType(paymentIntent),
    };
  });

exports.stripeCheckoutRedirect = functions
  .region("europe-west1")
  .https.onRequest((req, res) => {
    const status = String(req.query.status || "success") === "cancelled" ? "cancelled" : "success";
    const sessionId = encodeURIComponent(String(req.query.session_id || ""));
    const deepLink = `senicare://checkout-return?status=${status}&session_id=${sessionId}`;
    const isSuccess = status === "success";
    res.set("Content-Type", "text/html; charset=utf-8").status(200).send(`<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>SeniCare · Pago ${isSuccess ? "completado" : "cancelado"}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #F5F7FA; color: #1E293B; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; text-align: center; }
    .card { background: #fff; border-radius: 20px; padding: 28px 22px; max-width: 380px; width: 100%; box-shadow: 0 10px 30px rgba(15, 23, 42, 0.08); }
    .icon { font-size: 48px; margin-bottom: 12px; }
    h1 { font-size: 20px; margin: 0 0 8px; }
    p { font-size: 14px; color: #64748B; line-height: 1.5; margin: 0 0 20px; }
    a.btn { display: inline-block; background: #0D9488; color: #fff; text-decoration: none; font-weight: 700; padding: 14px 22px; border-radius: 12px; width: calc(100% - 44px); }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">${isSuccess ? "✅" : "↩️"}</div>
    <h1>${isSuccess ? "Pago recibido correctamente" : "Pago cancelado"}</h1>
    <p>${isSuccess ? "Vuelve a la app SeniCare para ver el código PIN y el resumen de tu reserva." : "Has vuelto antes de completar el pago. No se ha realizado ningún cargo."}</p>
    <a class="btn" href="${deepLink}">Volver a SeniCare</a>
  </div>
  <script>setTimeout(function(){ window.location.href = "${deepLink}"; }, 250);</script>
</body>
</html>`);
  });

// =========================================================================
// SERVER-VERIFIED PAYMENT CONFIRMATION, TIPS, 2FA, CLAIMS & RATINGS
// =========================================================================

exports.confirmClientBookingPayment = functions
  .region("europe-west1")
  .runWith({ secrets: [stripeSecret] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
    }
    const uid = context.auth.uid;
    const bookingIds = Array.isArray(data?.bookingIds)
      ? data.bookingIds.map((id) => String(id).trim()).filter(Boolean)
      : [];
    if (bookingIds.length === 0) {
      throw new functions.https.HttpsError("invalid-argument", "bookingIds requerido.");
    }

    const sessionId = typeof data?.sessionId === "string" ? data.sessionId.trim() : "";
    let paymentIntentId = typeof data?.paymentIntentId === "string" ? data.paymentIntentId.trim() : "";
    const transferGroup = typeof data?.transferGroup === "string" ? data.transferGroup.trim() : "";

    const stripe = require("stripe")(stripeSecret.value());
    let paymentIntent = null;
    let sessionPaymentStatus = null;
    let sessionCurrency = null;

    if (sessionId) {
      const session = await stripe.checkout.sessions.retrieve(sessionId, {
        expand: ["payment_intent.latest_charge"],
      });
      sessionPaymentStatus = session.payment_status;
      sessionCurrency = session.currency;
      if (session.payment_intent && typeof session.payment_intent === "object") {
        paymentIntent = session.payment_intent;
        paymentIntentId = paymentIntent.id;
      } else if (typeof session.payment_intent === "string") {
        paymentIntentId = session.payment_intent;
      }
    }

    if (!paymentIntent && paymentIntentId) {
      paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId, {
        expand: ["latest_charge"],
      });
    }

    if (!paymentIntent) {
      throw new functions.https.HttpsError("failed-precondition", "No se encontró el PaymentIntent en Stripe.");
    }

    const currency = String(paymentIntent.currency || sessionCurrency || "").toLowerCase();
    if (currency !== "eur") {
      throw new functions.https.HttpsError("failed-precondition", `Divisa no válida: ${currency}`);
    }

    const isPaid = paymentIntent.status === "succeeded" || sessionPaymentStatus === "paid";
    const isProcessing = !isPaid && paymentIntent.status === "processing";
    if (!isPaid && !isProcessing) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `El pago todavía no ha sido autorizado por Stripe (estado: ${paymentIntent.status}).`
      );
    }

    const db = admin.firestore();
    const docs = await Promise.all(bookingIds.map((id) => db.collection("bookings").doc(id).get()));
    const bookingIdSet = new Set(bookingIds);

    // Prevent cross-booking PaymentIntent replay attacks
    const existingPiDocs = await db.collection("bookings")
      .where("paymentIntentId", "==", paymentIntent.id)
      .get();
    for (const existingDoc of existingPiDocs.docs) {
      if (!bookingIdSet.has(existingDoc.id)) {
        const eb = existingDoc.data() || {};
        if (eb.paymentStatus === "paid" || (eb.status && eb.status !== "pendingPayment")) {
          throw new functions.https.HttpsError("permission-denied", "Este PaymentIntent ya fue utilizado en otra reserva.");
        }
      }
    }

    let expectedTotalEur = 0;
    const callerIsAdmin = await isAdminCaller(context);

    for (const snap of docs) {
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", `Reserva ${snap.id} no encontrada.`);
      }
      const b = snap.data() || {};
      if (!(await isFamilyAdmin(b.clientId, uid)) && !callerIsAdmin) {
        throw new functions.https.HttpsError("permission-denied", "Solo un Administrador familiar puede confirmar esta reserva.");
      }
      if (b.paymentIntentId && b.paymentIntentId !== paymentIntent.id) {
        throw new functions.https.HttpsError("permission-denied", "El PaymentIntent no corresponde a esta reserva.");
      }
      if (paymentIntent.metadata?.familyId && b.clientId && paymentIntent.metadata.familyId !== b.clientId && !callerIsAdmin) {
        throw new functions.https.HttpsError("permission-denied", "El PaymentIntent pertenece a otra cuenta familiar.");
      }
      expectedTotalEur += Number(b.totalPaid) || Number(b.cost) || 0;
    }

    const expectedCents = Math.round(expectedTotalEur * 100);
    const toleranceCents = Math.max(2, docs.length * 2);
    if ((paymentIntent.amount || 0) < (expectedCents - toleranceCents)) {
      throw new functions.https.HttpsError("permission-denied", "El importe pagado en Stripe es inferior al total de la reserva.");
    }

    const resolvedMethod = extractStripePaymentMethodType(paymentIntent);
    const resolvedPaymentStatus = isPaid ? "paid" : "processing";
    const batch = db.batch();

    for (const snap of docs) {
      const b = snap.data() || {};
      const isOfferBooking = Boolean(b.offerId || b.isJobOffer);
      const serverTargetStatus = isOfferBooking ? "confirmed" : "pending";
      const nextStatus = (b.status === "pendingPayment" || b.status === "pending")
        ? serverTargetStatus
        : b.status;
      const updatePayload = {
        status: nextStatus,
        paymentStatus: resolvedPaymentStatus,
        paymentIntentId: paymentIntent.id,
        paymentMethodType: resolvedMethod,
        escrowStatus: (!b.escrowStatus || b.escrowStatus === "none") ? "held" : b.escrowStatus,
      };
      if (transferGroup && !b.transferGroup) {
        updatePayload.transferGroup = transferGroup;
      }
      batch.update(snap.ref, updatePayload);
    }
    await batch.commit();

    return {
      success: true,
      paymentStatus: resolvedPaymentStatus,
      paymentIntentId: paymentIntent.id,
      paymentMethodType: resolvedMethod,
    };
  });

exports.createTipPaymentIntent = functions
  .region("europe-west1")
  .runWith({ secrets: [stripeSecret] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
    }
    const bookingId = typeof data?.bookingId === "string" ? data.bookingId.trim() : "";
    const tipAmount = Number(data?.tipAmount);
    if (!bookingId || !Number.isFinite(tipAmount) || tipAmount < 1 || tipAmount > 500) {
      throw new functions.https.HttpsError("invalid-argument", "La propina debe estar entre 1 € y 500 €.");
    }

    const db = admin.firestore();
    const bookingSnap = await db.collection("bookings").doc(bookingId).get();
    if (!bookingSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingSnap.data() || {};
    if (!(await isFamilyAdmin(booking.clientId, context.auth.uid))) {
      throw new functions.https.HttpsError("permission-denied", "Solo un Administrador familiar puede enviar propinas.");
    }

    const caregiverSnap = await db.collection("caregivers").doc(booking.caregiverId).get();
    if (!caregiverSnap.exists || !caregiverSnap.data()?.stripeAccountId) {
      throw new functions.https.HttpsError("failed-precondition", "El cuidador no tiene cuenta bancaria (Stripe) configurada.");
    }

    const stripe = require("stripe")(stripeSecret.value());
    const customerInfo = await getOrCreateStripeCustomerAndSession(stripe, context.auth);
    const amountInCents = Math.round(tipAmount * 100);
    const transferGroup = `tip_${bookingId}_${Date.now()}`;

    const { paymentIntent, requestedMethod, fallbackUsed } = await createPaymentIntentWithPreference(stripe, {
      amountInCents,
      currency: "eur",
      transferGroup,
      preferredMethod: typeof data?.preferredMethod === "string" ? data.preferredMethod : "auto",
      customerId: customerInfo.customerId,
      metadata: {
        type: "tip",
        bookingId,
        familyId: booking.clientId,
        caregiverId: booking.caregiverId,
        paidByUid: context.auth.uid,
      },
      description: `SeniCare · Propina 100% íntegra para ${booking.caregiverName || "cuidador"}`,
    });

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
      transferGroup,
      customerId: customerInfo.customerId || null,
      customerSessionClientSecret: customerInfo.customerSessionClientSecret || null,
      ephemeralKeySecret: customerInfo.ephemeralKeySecret || null,
      requestedMethod,
      fallbackUsed,
    };
  });

exports.confirmTipPayment = functions
  .region("europe-west1")
  .runWith({ secrets: [stripeSecret] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
    }
    const bookingId = typeof data?.bookingId === "string" ? data.bookingId.trim() : "";
    const paymentIntentId = typeof data?.paymentIntentId === "string" ? data.paymentIntentId.trim() : "";
    if (!bookingId || !paymentIntentId) {
      throw new functions.https.HttpsError("invalid-argument", "bookingId y paymentIntentId son obligatorios.");
    }

    const stripe = require("stripe")(stripeSecret.value());
    const pi = await stripe.paymentIntents.retrieve(paymentIntentId, { expand: ["latest_charge"] });
    if (!pi || pi.status !== "succeeded") {
      throw new functions.https.HttpsError("failed-precondition", "El pago de la propina no está confirmado en Stripe.");
    }
    if (pi.metadata?.type !== "tip" || pi.metadata?.bookingId !== bookingId) {
      throw new functions.https.HttpsError("permission-denied", "El PaymentIntent no corresponde a esta propina.");
    }

    await applyTipSettlement(stripe, pi);
    return {
      success: true,
      amountEur: (pi.amount_received || pi.amount || 0) / 100,
    };
  });

exports.setupAdmin2FA = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  const email = (context.auth.token?.email || "").trim();
  const verified = context.auth.token?.email_verified === true;
  if (!email || !verified) {
    throw new functions.https.HttpsError("permission-denied", "Tu correo debe estar verificado.");
  }
  if (!(await isAdminCaller(context))) {
    throw new functions.https.HttpsError("permission-denied", "Solo administradores autorizados.");
  }

  const secret = String(data?.secret || "").trim().toUpperCase();
  const code = String(data?.code || "").trim();
  if (!/^[A-Z2-7]{16,64}$/.test(secret)) {
    throw new functions.https.HttpsError("invalid-argument", "Secreto TOTP inválido.");
  }
  if (!verifyTotpCode(secret, code)) {
    throw new functions.https.HttpsError("invalid-argument", "El código de verificación 2FA es incorrecto.");
  }

  const db = admin.firestore();
  const adminRef = db.collection("admins").doc(email);
  await adminRef.set({
    email,
    "2faEnabled": true,
    secret: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  await adminRef.collection("private").doc("totp").set({
    secret,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await mergeUserClaims(context.auth.uid, { admin: true });
  return { success: true };
});

exports.verifyAdmin2FA = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  const email = (context.auth.token?.email || "").trim();
  if (!email || !(await isAdminCaller(context))) {
    throw new functions.https.HttpsError("permission-denied", "Solo administradores verificados.");
  }
  await checkRateLimit(`admin2fa:${context.auth.uid}`, 5, 5 * 60 * 1000);
  const code = String(data?.code || "").trim();
  const db = admin.firestore();
  const adminRef = db.collection("admins").doc(email);
  const privateRef = adminRef.collection("private").doc("totp");

  let secret = "";
  const privateSnap = await privateRef.get();
  if (privateSnap.exists && privateSnap.data()?.secret) {
    secret = String(privateSnap.data().secret);
  } else {
    const publicSnap = await adminRef.get();
    if (publicSnap.exists && publicSnap.data()?.secret) {
      secret = String(publicSnap.data().secret);
      // Migrar automáticamente el secreto legacy al documento privado
      await privateRef.set({ secret, migratedAt: admin.firestore.FieldValue.serverTimestamp() });
      await adminRef.set({ secret: admin.firestore.FieldValue.delete(), "2faEnabled": true }, { merge: true });
    }
  }

  if (!secret) {
    throw new functions.https.HttpsError("failed-precondition", "2FA no configurado para este administrador.");
  }
  if (!verifyTotpCode(secret, code)) {
    throw new functions.https.HttpsError("permission-denied", "Código 2FA incorrecto.");
  }

  await mergeUserClaims(context.auth.uid, { admin: true });
  return { success: true };
});

exports.syncUserClaims = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  const uid = context.auth.uid;
  const db = admin.firestore();
  const patch = {};

  if (await isAdminCaller(context)) {
    patch.admin = true;
  } else {
    patch.admin = null;
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const activeFamilyId = userSnap.data()?.activeFamilyId;
  if (activeFamilyId && (await isFamilyMember(activeFamilyId, uid))) {
    patch.familyId = activeFamilyId;
  } else {
    patch.familyId = null;
  }

  await mergeUserClaims(uid, patch);
  return { success: true, familyId: patch.familyId || null, isAdmin: patch.admin === true };
});

exports.syncCaregiverRatingOnReviewCreated = onDocumentCreated({
  document: "reviews/{reviewId}",
  region: "europe-west1"
}, async (event) => {
  const review = event.data?.data();
  if (!review || !review.caregiverId) return null;
  const rating = Number(review.rating);
  if (!Number.isFinite(rating) || rating < 1 || rating > 5) return null;

  const db = admin.firestore();
  const caregiverRef = db.collection("caregivers").doc(review.caregiverId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(caregiverRef);
    if (!snap.exists) return;
    const data = snap.data() || {};
    const currentRating = Number(data.rating) || 0;
    const currentReviewsCount = Number(data.reviewsCount) || 0;
    const newReviewsCount = currentReviewsCount + 1;
    const newRating = ((currentRating * currentReviewsCount) + rating) / newReviewsCount;
    tx.update(caregiverRef, {
      rating: newRating,
      reviewsCount: newReviewsCount,
    });
  });
  return null;
});
