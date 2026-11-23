const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const crypto = require("crypto");
const { defineSecret } = require("firebase-functions/params");

const stripeSecret = defineSecret("STRIPE_SECRET_KEY");
const webhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
const MASTER_ADMIN_EMAIL = "maverick6576@gmail.com";
const STANDARD_CLIENT_FEE_RATE = 0.03;

admin.initializeApp();

async function getAdminDocForContext(context) {
  if (!context || !context.auth) return { isRegistered: false, adminDoc: null, email: "" };
  const email = (context.auth.token?.email || "").trim().toLowerCase();
  const verified = context.auth.token?.email_verified === true;
  if (!email || !verified) return { isRegistered: false, adminDoc: null, email: "" };
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(email).get();
  if (adminDoc.exists) return { isRegistered: true, adminDoc, email };
  const originalEmail = (context.auth.token?.email || "").trim();
  if (originalEmail !== email) {
    const exactDoc = await db.collection("admins").doc(originalEmail).get();
    if (exactDoc.exists) return { isRegistered: true, adminDoc: exactDoc, email: originalEmail };
  }
  if (email === MASTER_ADMIN_EMAIL) {
    return { isRegistered: true, adminDoc: null, email };
  }
  return { isRegistered: false, adminDoc: null, email };
}

async function isAdminCaller(context) {
  if (!context || !context.auth) return false;
  if (context.auth.token?.admin !== true || context.auth.token?.admin2fa !== true) {
    return false;
  }
  const { isRegistered, adminDoc } = await getAdminDocForContext(context);
  if (!isRegistered || !adminDoc || !adminDoc.exists) return false;
  return true;
}

function isStripeConnectAccountReady(account) {
  return Boolean(
    account &&
    account.details_submitted &&
    account.charges_enabled &&
    account.payouts_enabled &&
    account.capabilities?.transfers === "active"
  );
}

async function checkCaregiverConnectReadiness(stripe, caregiverDoc) {
  if (!caregiverDoc || !caregiverDoc.exists) {
    return { ready: false, accountId: "", reason: "caregiver_doc_missing" };
  }
  const cgData = caregiverDoc.data() || {};
  const accountId = String(cgData.stripeAccountId || "").trim();
  if (!accountId) {
    return { ready: false, accountId: "", reason: "stripe_account_missing" };
  }
  if (cgData.isKycVerified === true && cgData.transfersCapabilityStatus === "active") {
    return { ready: true, accountId, reason: null };
  }
  try {
    const account = await stripe.accounts.retrieve(accountId);
    if (isStripeConnectAccountReady(account)) {
      await caregiverDoc.ref.set({
        isKycVerified: true,
        chargesEnabled: Boolean(account.charges_enabled),
        payoutsEnabled: Boolean(account.payouts_enabled),
        detailsSubmitted: Boolean(account.details_submitted),
        transfersCapabilityStatus: account.capabilities?.transfers || "active",
      }, { merge: true }).catch(() => {});
      return { ready: true, accountId, reason: null };
    }
    return {
      ready: false,
      accountId,
      reason: `connect_not_ready(transfers=${account?.capabilities?.transfers || "inactive"},payouts=${Boolean(account?.payouts_enabled)})`,
    };
  } catch (err) {
    return { ready: false, accountId, reason: `stripe_retrieve_error:${err.message}` };
  }
}

async function acceptJobOfferOnPayment(db, { offerId, applicationId, caregiverId }) {
  if (!offerId || !caregiverId) return;
  try {
    const offerRef = db.collection("job_offers").doc(offerId);
    const offerSnap = await offerRef.get();
    if (!offerSnap.exists) return;
    const offerData = offerSnap.data() || {};
    const offerUpdate = {
      acceptedCaregiverId: caregiverId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (applicationId) {
      offerUpdate.acceptedApplicationId = applicationId;
    }
    if (offerData.status === "open") {
      offerUpdate.status = "inProgress";
    }
    await offerRef.set(offerUpdate, { merge: true });

    const appsSnap = await offerRef.collection("applications").get();
    if (!appsSnap.empty) {
      const batch = db.batch();
      let hasUpdates = false;
      for (const appDoc of appsSnap.docs) {
        const appData = appDoc.data() || {};
        const isWinner = (applicationId && appDoc.id === applicationId) ||
          (!applicationId && appData.caregiverId === caregiverId);
        if (isWinner) {
          if (appData.status !== "accepted") {
            batch.update(appDoc.ref, {
              status: "accepted",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            hasUpdates = true;
          }
        } else if (appData.status === "pending" || !appData.status) {
          batch.update(appDoc.ref, {
            status: "rejected",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          hasUpdates = true;
        }
      }
      if (hasUpdates) {
        await batch.commit();
      }
    }
  } catch (err) {
    console.warn(`acceptJobOfferOnPayment(${offerId}) warning:`, err.message);
  }
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

function getMadridDateParts(dateOrMs) {
  const d = dateOrMs instanceof Date ? dateOrMs : new Date(dateOrMs);
  const parts = {};
  for (const part of madridDateTimeFormatter.formatToParts(d)) {
    if (part.type !== "literal") {
      parts[part.type] = part.value;
    }
  }
  const hour = parts.hour === "24" ? 0 : Number(parts.hour);
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    ymd: `${parts.year}-${parts.month}-${parts.day}`,
    hour,
    minute: Number(parts.minute),
    second: Number(parts.second),
  };
}

function getMadridOffsetMs(utcMs) {
  const parts = getMadridDateParts(utcMs);
  const asUtc = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second
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
  if (!booking || !booking.paymentIntentId) return false;
  try {
    const pi = await stripe.paymentIntents.retrieve(booking.paymentIntentId);
    return Boolean(pi && pi.status === "succeeded" && String(pi.currency || "eur").toLowerCase() === "eur");
  } catch (e) {
    console.warn(`Could not verify PaymentIntent ${booking.paymentIntentId}:`, e.message);
    return false;
  }
}

function generateBookingPin() {
  return String(crypto.randomInt(1000, 10000));
}

function hashPin(pin, salt = "") {
  const cleanPin = String(pin || "").trim();
  if (salt) {
    return crypto.createHmac("sha256", String(salt)).update(cleanPin).digest("hex");
  }
  return crypto.createHash("sha256").update(cleanPin).digest("hex");
}

function computeServerCommissionRate(accumulatedHours, urgencyBonusRate = 0) {
  const hours = Number(accumulatedHours) || 0;
  let baseTierRate = 0.18;
  if (hours > 80) {
    baseTierRate = 0.06;
  } else if (hours > 20) {
    baseTierRate = 0.12;
  }
  const safeBonus = Math.min(Math.max(Number(urgencyBonusRate) || 0, 0), 0.10);
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
      .where("status", "in", ["confirmed", "disputed"])
      .get();
    const hasConfirmedPaidBooking = activeSnap.docs.some((d) => {
      const b = d.data() || {};
      return b.paymentStatus === "paid" || b.escrowStatus === "held" || b.escrowStatus === "disputed";
    });
    if (hasConfirmedPaidBooking) {
      await accessRef.set({
        caregiverId,
        active: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } else {
      const disputedSnap = await db.collection("bookings")
        .where("clientId", "==", clientId)
        .where("caregiverId", "==", caregiverId)
        .where("escrowStatus", "in", ["disputed", "stripe_disputed"])
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
  const uid = context.auth.uid;
  const stripe = require("stripe")(stripeSecret.value());
  try {
    const db = admin.firestore();
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists || userSnap.data()?.role !== "caregiver") {
      throw new functions.https.HttpsError("permission-denied", "Solo usuarios con rol de cuidador pueden crear una cuenta Stripe Connect.");
    }
    const caregiverRef = db.collection("caregivers").doc(uid);
    const caregiverSnap = await caregiverRef.get();
    if (caregiverSnap.exists && caregiverSnap.data().stripeAccountId) {
      return { accountId: caregiverSnap.data().stripeAccountId, existing: true };
    }
    const email = context.auth.token.email || "cuidador@senicare.app";
    const account = await stripe.accounts.create(
      {
        type: "express",
        country: "ES",
        email: email,
        capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
        business_type: "individual",
        metadata: { firebaseUid: uid },
      },
      { idempotencyKey: `connect_account_${uid}` }
    );
    await caregiverRef.set({ stripeAccountId: account.id }, { merge: true });
    return { accountId: account.id };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Error in createConnectAccount:", error);
    throw new functions.https.HttpsError("internal", "No se pudo configurar la cuenta de cobros en este momento.");
  }
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
    const account = await stripe.accounts.retrieve(accountId);
    if (!callerIsAdmin && account?.metadata?.firebaseUid && account.metadata.firebaseUid !== context.auth.uid) {
      throw new functions.https.HttpsError("permission-denied", "No tienes permiso para acceder a esta cuenta Stripe Connect.");
    }
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
    console.error("Error in getStripeAccountLink:", error);
    throw new functions.https.HttpsError("internal", "No se pudo generar el enlace de Stripe Connect.");
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
    if (account?.metadata?.firebaseUid && account.metadata.firebaseUid !== uid) {
      throw new functions.https.HttpsError("permission-denied", "La cuenta Stripe Connect no corresponde a tu usuario.");
    }
    
    const transfersStatus = account.capabilities?.transfers || "inactive";
    const isVerified = isStripeConnectAccountReady(account);
    
    await admin.firestore().collection("caregivers").doc(uid).update({
      isKycVerified: isVerified,
      chargesEnabled: Boolean(account.charges_enabled),
      payoutsEnabled: Boolean(account.payouts_enabled),
      detailsSubmitted: Boolean(account.details_submitted),
      transfersCapabilityStatus: transfersStatus,
    });
    
    return {
      isVerified,
      chargesEnabled: Boolean(account.charges_enabled),
      payoutsEnabled: Boolean(account.payouts_enabled),
      transfersCapabilityStatus: transfersStatus,
    };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Error in syncStripeKycStatus:", error);
    throw new functions.https.HttpsError("internal", "No se pudo sincronizar el estado de verificación con Stripe.");
  }
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
      const customer = await stripe.customers.create(
        {
          email: tokenEmail,
          name: tokenName,
          metadata: { firebaseUid: uid },
        },
        { idempotencyKey: `customer_${uid}` }
      );
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
    idempotencyKeyBase = null,
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

  const keyPrefix = idempotencyKeyBase || `pi_${transferGroup || Date.now()}_${baseParams.amount}_${normalizedMethod}`;
  const primaryOpts = { idempotencyKey: `${keyPrefix}_primary`.slice(0, 250) };
  const fallbackOpts = { idempotencyKey: `${keyPrefix}_fallback`.slice(0, 250) };

  const explicitTypes = PAYMENT_PREFERENCE_METHOD_TYPES[normalizedMethod];
  if (explicitTypes && explicitTypes.length > 0) {
    try {
      const paymentIntent = await stripe.paymentIntents.create(
        {
          ...baseParams,
          payment_method_types: explicitTypes,
        },
        primaryOpts
      );
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
      const fallbackIntent = await stripe.paymentIntents.create(
        {
          ...baseParams,
          automatic_payment_methods: { enabled: true },
        },
        fallbackOpts
      );
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
    const paymentIntent = await stripe.paymentIntents.create(autoParams, primaryOpts);
    return {
      paymentIntent,
      requestedMethod: normalizedMethod,
      fallbackUsed: false,
    };
  } catch (autoErr) {
    console.warn("automatic_payment_methods fallback to ['card']:", autoErr.message);
    const cardIntent = await stripe.paymentIntents.create(
      {
        ...baseParams,
        payment_method_types: ["card"],
      },
      fallbackOpts
    );
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
      if (!Number.isFinite(parsedHours) || parsedHours < 0.5 || parsedHours > 24) {
        throw new functions.https.HttpsError("invalid-argument", `Duración de sesión inválida (mínimo 30 min): ${slot}`);
      }
      const startMadrid = getMadridDateParts(startDt);
      const endMadrid = getMadridDateParts(endDt);
      normalizedSessions.push({
        day,
        slot,
        startMs: startDt.getTime(),
        endMs: endDt.getTime(),
        hours: Math.round(parsedHours * 100) / 100,
        startHour: startMadrid.hour,
        endHour: endMadrid.hour === 0 && endMadrid.ymd !== startMadrid.ymd
          ? 24
          : (endMadrid.minute > 0 ? endMadrid.hour + 1 : endMadrid.hour),
      });
    }

    const preferredMethod = typeof data?.preferredMethod === "string" ? data.preferredMethod.toLowerCase().trim() : "auto";
    if (preferredMethod === "sepa_debit") {
      const earliestStartMs = Math.min(...normalizedSessions.map((s) => s.startMs));
      const hoursUntilEarliestStart = (earliestStartMs - Date.now()) / (3600 * 1000);
      if (hoursUntilEarliestStart < 120) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "El adeudo directo SEPA solo está disponible para reservas con al menos 5 días (120 horas) de antelación."
        );
      }
    }

    const sanitizedChecklist = Array.isArray(data?.checklist)
      ? data.checklist.slice(0, 30).map((item, idx) => {
          const title = typeof item === "string" ? item.trim() : String(item?.title || "").trim();
          return title ? { id: `task_${idx + 1}`, title: title.slice(0, 200), completed: false } : null;
        }).filter(Boolean)
      : [];

    let createdPaymentIntentId = null;
    let createdCheckoutSessionId = null;
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
        const cgStripeAccount = await stripe.accounts.retrieve(stripeAccountId);
        if (!isStripeConnectAccountReady(cgStripeAccount)) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "La cuenta de cobros del cuidador aún no tiene habilitados los pagos y transferencias en Stripe."
          );
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
            const offerStartDate = offerData.startDate?.toDate ? offerData.startDate.toDate() : null;
            const offerCreatedAt = offerData.createdAt?.toDate ? offerData.createdAt.toDate() : null;
            const isShortNoticeOffer = Boolean(
              offerStartDate &&
              offerCreatedAt &&
              (offerStartDate.getTime() - offerCreatedAt.getTime()) < (24 * 60 * 60 * 1000)
            );
            const isServerUrgent = offerData.urgentPromotedByServer === true || isShortNoticeOffer;
            if (isServerUrgent) {
              const rawUrgency = Number(offerData.urgencyBonusRate);
              urgencyBonusRate = Number.isFinite(rawUrgency) && rawUrgency > 0
                ? Math.min(rawUrgency, 0.10)
                : 0.10;
            } else {
              urgencyBonusRate = 0.0;
            }
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
        const pinSalt = crypto.randomBytes(16).toString("hex");
        const sharedPinHash = hashPin(sharedPin, pinSalt);
        const qrToken = crypto.randomBytes(16).toString("hex");
        const useCheckoutSession = data?.useCheckoutSession === true || preferredMethod === "bizum";

        let totalPaidOverallCents = 0;
        const bookingsToCreate = [];
        const bookingIds = [];

        for (const session of normalizedSessions) {
            const costCents = Math.round(pricePerHour * session.hours * discountMultiplier * 100);
            const clientFeeCents = Math.round(costCents * clientFeeRate);
            const commissionAmountCents = Math.round(costCents * commissionRate);
            const caregiverPayoutCents = costCents - commissionAmountCents;
            const totalPaidCents = costCents + clientFeeCents;

            const cost = costCents / 100;
            const clientFee = clientFeeCents / 100;
            const commissionAmount = commissionAmountCents / 100;
            const caregiverPayout = caregiverPayoutCents / 100;
            const totalPaid = totalPaidCents / 100;

            totalPaidOverallCents += totalPaidCents;
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
                    careChecklist: sanitizedChecklist,
                    status: "pendingPayment",
                    paymentStatus: "pending",
                    transferGroup,
                    escrowStatus: "none",
                    disputeEscalated: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    isReviewed: false,
                },
            });
        }

        const amountInCents = totalPaidOverallCents;
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
          const csKeyBase = `cs_secure_${transferGroup}_${bookingIds[0] || uid}`;
          try {
            const methodList = PAYMENT_PREFERENCE_METHOD_TYPES[preferredMethod];
            session = await stripe.checkout.sessions.create(
              {
                ...sessionBase,
                ...(methodList ? { payment_method_types: methodList } : {}),
              },
              { idempotencyKey: `${csKeyBase}_primary`.slice(0, 250) }
            );
          } catch (explicitErr) {
            console.warn(`Secure checkout '${preferredMethod}' fallback:`, explicitErr.message);
            fallbackUsed = true;
            session = await stripe.checkout.sessions.create(
              sessionBase,
              { idempotencyKey: `${csKeyBase}_fallback`.slice(0, 250) }
            );
          }

          createdCheckoutSessionId = session.id;
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
            idempotencyKeyBase: `pi_secure_${transferGroup}_${bookingIds[0] || uid}`,
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

        // Persist bookings, secrets, and slot locks atomically (caregiver_access is granted only once confirmed & paid)
        await db.runTransaction(async (tx) => {
          const slotChecks = [];
          const existingDayBookings = [];
          if (!offerId) {
            const uniqueDays = [...new Set(bookingsToCreate.map((b) => b.session.day))];
            for (const d of uniqueDays) {
              const q = db.collection("bookings")
                .where("caregiverId", "==", caregiverId)
                .where("day", "==", d)
                .where("status", "in", ["pendingPayment", "pending", "confirmed"]);
              const snap = await tx.get(q);
              snap.docs.forEach((docSnap) => {
                existingDayBookings.push(docSnap.data() || {});
              });
            }

            for (const item of bookingsToCreate) {
              const { day, startMs, endMs, startHour, endHour } = item.session;

              // 1) Verificar solapamiento real contra reservas activas del cuidador ese día
              for (const existing of existingDayBookings) {
                const exStart = parseBookingStartDateTime(existing.day, existing.slot);
                const exEnd = parseBookingEndDateTime(existing.day, existing.slot);
                if (exStart && exEnd && startMs < exEnd.getTime() && endMs > exStart.getTime()) {
                  throw new functions.https.HttpsError(
                    "failed-precondition",
                    `El horario ${item.session.slot} (${day}) se solapa con otra reserva ya existente.`
                  );
                }
              }

              // 2) Comprobar disponibilidad horaria legacy si el slot es de horas exactas (en Europe/Madrid)
              const isExactHour = getMadridDateParts(startMs).minute === 0 && getMadridDateParts(endMs).minute === 0;
              if (isExactHour) {
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

          // Registrar bloqueo exacto por intervalo para franjas flexibles
          if (!offerId) {
            for (const item of bookingsToCreate) {
              const { day, startMs, endMs } = item.session;
              const blockRef = db.collection("caregivers").doc(caregiverId)
                .collection("availability").doc(day)
                .collection("slots").doc(`booked_${item.ref.id}`);
              tx.set(blockRef, {
                id: `booked_${item.ref.id}`,
                dateTime: admin.firestore.Timestamp.fromMillis(startMs),
                endTime: admin.firestore.Timestamp.fromMillis(endMs),
                isAvailable: false,
                lockedByBookingId: item.ref.id,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          }

          for (const item of bookingsToCreate) {
            if (createdPaymentIntentId) item.data.paymentIntentId = createdPaymentIntentId;
            if (createdCheckoutSessionId) item.data.checkoutSessionId = createdCheckoutSessionId;
            item.data.paymentMethodType = resolvedMethod;
            tx.set(item.ref, item.data);
            tx.set(item.secretRef, {
              bookingPin: sharedPin,
              bookingPinHash: sharedPinHash,
              pinSalt,
              qrToken,
              clientId: targetFamilyId,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        });

        return {
          ...responsePayload,
          bookingIds,
          bookingPin: sharedPin,
          totalEur: totalPaidOverallCents / 100,
          discountApplied: discountMultiplier < 1.0,
          commissionRate,
        };
    } catch (error) {
        if (createdCheckoutSessionId) {
          try {
            await stripe.checkout.sessions.expire(createdCheckoutSessionId);
          } catch (_) {}
        }
        if (createdPaymentIntentId) {
          try {
            await stripe.paymentIntents.cancel(createdPaymentIntentId);
          } catch (_) {}
        }
        if (error instanceof functions.https.HttpsError) throw error;
        console.error("Secure Booking Error: ", error);
        throw new functions.https.HttpsError("internal", "No se pudo procesar la reserva en este momento. Inténtalo de nuevo.");
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
    ? [...new Set(data.bookingIds.map((b) => String(b).trim()).filter(Boolean))]
    : [];
  if (bookingIds.length === 0) {
    throw new functions.https.HttpsError("failed-precondition", "Usa createSecureBooking con reservas registradas en el servidor.");
  }

  const preferredMethod = typeof data?.preferredMethod === "string" ? data.preferredMethod.toLowerCase().trim() : "auto";
  const db = admin.firestore();
  const docs = await Promise.all(bookingIds.map((id) => db.collection("bookings").doc(id).get()));
  let computedTotalCents = 0;
  let transferGroup = `booking_${Date.now()}`;
  let caregiverId = "";
  const oldPiIds = new Set();
  const oldSessionIds = new Set();

  for (const snap of docs) {
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    const b = snap.data() || {};
    if (b.clientId !== familyId) throw new functions.https.HttpsError("permission-denied", "La reserva no pertenece a esta familia.");
    if (b.paymentStatus === "paid" || b.paymentStatus === "processing") {
      throw new functions.https.HttpsError("failed-precondition", "La reserva ya está pagada o su pago está en procesamiento.");
    }
    if (["cancelled", "cancelledLate", "expired"].includes(b.status)) {
      throw new functions.https.HttpsError("failed-precondition", "La reserva está cancelada o ha expirado.");
    }
    if (preferredMethod === "sepa_debit") {
      const startDt = parseBookingStartDateTime(b.day, b.slot);
      if (!startDt || ((startDt.getTime() - Date.now()) / (3600 * 1000)) < 120) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "El adeudo directo SEPA solo está disponible para reservas con al menos 5 días (120 horas) de antelación."
        );
      }
    }
    const costCents = Math.round((Number(b.cost) || 0) * 100);
    const feeRate = Number(b.clientFeeRate) || STANDARD_CLIENT_FEE_RATE;
    const bookingPaidCents = Number(b.totalPaid) > 0
      ? Math.round(Number(b.totalPaid) * 100)
      : (costCents + Math.round(costCents * feeRate));
    computedTotalCents += bookingPaidCents;
    if (b.transferGroup) transferGroup = b.transferGroup;
    if (b.caregiverId) caregiverId = b.caregiverId;
    if (b.paymentIntentId) oldPiIds.add(b.paymentIntentId);
    if (b.checkoutSessionId) oldSessionIds.add(b.checkoutSessionId);
  }

  const amountInCents = computedTotalCents;
  if (!Number.isFinite(amountInCents) || amountInCents < 50) {
    throw new functions.https.HttpsError("invalid-argument", "El importe mínimo es 0,50 €.");
  }

  const stripe = require("stripe")(stripeSecret.value());
  try {
    for (const oldSessionId of oldSessionIds) {
      await stripe.checkout.sessions.expire(oldSessionId).catch(() => {});
    }
    for (const oldPiId of oldPiIds) {
      try {
        const oldPi = await stripe.paymentIntents.retrieve(oldPiId);
        if (oldPi && (oldPi.status === "succeeded" || oldPi.status === "processing")) {
          throw new functions.https.HttpsError("failed-precondition", "El pago de esta reserva ya se ha completado o está en procesamiento.");
        }
        if (oldPi && ["requires_payment_method", "requires_confirmation", "requires_action", "requires_capture"].includes(oldPi.status)) {
          await stripe.paymentIntents.cancel(oldPiId);
        }
      } catch (piErr) {
        if (piErr instanceof functions.https.HttpsError) throw piErr;
      }
    }

    const prevKeyPart = [...oldPiIds, ...oldSessionIds].join("_").slice(0, 60) || "init";
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
      idempotencyKeyBase: `pi_retry_${bookingIds[0]}_${amountInCents}_${preferredMethod}_${prevKeyPart}`,
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
    throw new functions.https.HttpsError("internal", "No se pudo iniciar el pago en este momento. Inténtalo de nuevo.");
  }
});

async function reopenBookingSlots(caregiverId, day, slotRange) {
  if (!caregiverId || !day || !slotRange) return;
  try {
    const cgRef = admin.firestore().collection("caregivers").doc(caregiverId).collection("availability");

    const startDt = parseBookingStartDateTime(day, slotRange);
    const endDt = parseBookingEndDateTime(day, slotRange);
    if (slotRange.includes("-") && startDt && endDt && endDt.getTime() > startDt.getTime()) {
      const batch = admin.firestore().batch();
      const daySlotsSnap = await cgRef.doc(day).collection("slots").get();
      daySlotsSnap.docs.forEach((sDoc) => {
        if (sDoc.id.startsWith("booked_")) {
          const sData = sDoc.data() || {};
          const sStart = sData.dateTime?.toDate ? sData.dateTime.toDate().getTime() : null;
          const sEnd = sData.endTime?.toDate ? sData.endTime.toDate().getTime() : null;
          if (sStart && sEnd && sStart === startDt.getTime() && sEnd === endDt.getTime()) {
            batch.delete(sDoc.ref);
          }
        }
      });

      const totalHours = Math.min(24, Math.max(1, Math.ceil((endDt.getTime() - startDt.getTime()) / (3600 * 1000))));
      for (let i = 0; i < totalHours; i++) {
        const current = new Date(startDt.getTime() + i * 3600 * 1000);
        const madridParts = getMadridDateParts(current);
        const dayStr = madridParts.ymd;
        const hourStr = `${String(madridParts.hour).padStart(2, "0")}:00`;
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
  if (booking.paymentStatus !== "paid") {
    throw new functions.https.HttpsError("failed-precondition", "El pago de la reserva debe estar confirmado y liquidado antes de realizar el check-in.");
  }

  const startDt = parseBookingStartDateTime(booking.day, booking.slot);
  const endDt = parseBookingEndDateTime(booking.day, booking.slot);
  if (startDt && endDt) {
    // Cloud Functions run in UTC; bookings are scheduled in Europe/Madrid local time (+1h/+2h)
    const nowMs = Date.now();
    const minAllowedMs = startDt.getTime() - (150 * 60 * 1000);
    const maxAllowedMs = endDt.getTime();
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
    const storedHash = String(secretData.bookingPinHash || booking.bookingPinHash || "");
    const enteredHash = hashPin(enteredPin, secretData.pinSalt || "");
    const legacyUnsaltedHash = secretData.pinSalt ? hashPin(enteredPin, "") : enteredHash;
    const plainFallback = String(secretData.bookingPin || "").trim();
    const hashMatches = (storedHash.length === enteredHash.length &&
      storedHash.length > 0 &&
      crypto.timingSafeEqual(Buffer.from(storedHash), Buffer.from(enteredHash))) ||
      (storedHash.length === legacyUnsaltedHash.length &&
      storedHash.length > 0 &&
      crypto.timingSafeEqual(Buffer.from(storedHash), Buffer.from(legacyUnsaltedHash)));
    const plainMatches = plainFallback.length === 4 &&
      crypto.timingSafeEqual(Buffer.from(plainFallback), Buffer.from(enteredPin));
    if (!hashMatches && !plainMatches) {
      throw new functions.https.HttpsError("permission-denied", "PIN incorrecto. Comprueba los 4 dígitos facilitados por la familia.");
    }
  } else {
    const qrValue = String(data?.qrValue || "").trim();
    const expectedQrToken = typeof secretData.qrToken === "string" ? secretData.qrToken.trim() : "";
    const validQr = expectedQrToken.length > 0 &&
      qrValue.length === expectedQrToken.length &&
      crypto.timingSafeEqual(Buffer.from(qrValue), Buffer.from(expectedQrToken));
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

/**
 * Fichaje de salida (Check-out) obligatorio por parte del cuidador:
 * - Exige resumen obligatorio en el diario (careNotes no vacío, máx. 2000 caracteres).
 * - Si ficha más de 15 minutos antes de la hora teórica de fin: penalización económica,
 *   se le paga únicamente el tiempo real trabajado (prorrateado por minuto en céntimos enteros),
 *   la app mantiene su comisión porcentual sobre lo trabajado, se devuelve el importe no trabajado
 *   al cliente y se mantiene escrowStatus: "held" para liquidar al cuidador por la vía normal/24h.
 */
exports.recordBookingCheckOut = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const bookingId = typeof data?.bookingId === "string" ? data.bookingId.trim() : "";
  const careNotes = typeof data?.careNotes === "string" ? data.careNotes.trim() : "";

  if (!bookingId) {
    throw new functions.https.HttpsError("invalid-argument", "bookingId requerido.");
  }
  if (!careNotes) {
    throw new functions.https.HttpsError("invalid-argument", "Es obligatorio escribir un resumen en el diario para registrar la salida.");
  }
  if (careNotes.length > 2000) {
    throw new functions.https.HttpsError("invalid-argument", "El resumen del diario no puede superar los 2.000 caracteres.");
  }

  await checkRateLimit(`checkout_record:${uid}:${bookingId}`, 10, 10 * 60 * 1000);

  const db = admin.firestore();
  const stripe = require("stripe")(stripeSecret.value());
  const bookingRef = db.collection("bookings").doc(bookingId);
  let lockAcquired = false;

  try {
    const lockRes = await acquireEscrowLock(bookingRef, "recordBookingCheckOut", async (b) => {
      if (b.caregiverId !== uid) {
        throw new functions.https.HttpsError("permission-denied", "Solo el cuidador asignado puede registrar el check-out.");
      }
      if (b.checkOutTime) {
        return { skip: true, alreadyCheckedOut: true };
      }
      if (!b.checkInTime) {
        throw new functions.https.HttpsError("failed-precondition", "No se puede fichar la salida sin haber realizado el check-in.");
      }
      if (b.status !== "confirmed") {
        throw new functions.https.HttpsError("failed-precondition", "Solo se puede registrar el check-out en una reserva confirmada.");
      }
      if (b.escrowStatus !== "held") {
        throw new functions.https.HttpsError("failed-precondition", "La custodia de esta reserva no está activa para registrar el check-out.");
      }
      if (b.paymentStatus !== "paid") {
        throw new functions.https.HttpsError("failed-precondition", "El pago de esta reserva aún no está confirmado.");
      }
      return {};
    });

    if (lockRes.skip && lockRes.alreadyCheckedOut) {
      return { success: true, alreadyCheckedOut: true };
    }
    lockAcquired = lockRes.acquired;
    const booking = lockRes.booking;

    const startDt = parseBookingStartDateTime(booking.day, booking.slot);
    const endDt = parseBookingEndDateTime(booking.day, booking.slot);
    const now = new Date();
    const nowMs = now.getTime();

    let isEarlyCheckOut = false;
    let minutesEarly = 0;
    let earlyRefundAmount = 0;
    let earlyRefundCents = 0;
    const originalCostCents = Number.isFinite(Number(booking.originalCostCents))
      ? Math.round(Number(booking.originalCostCents))
      : Math.round((Number(booking.cost) || 0) * 100);
    let updatedCost = originalCostCents / 100;
    let updatedCommission = Number(booking.caregiverCommissionAmount) || 0;
    let updatedPayout = Number(booking.caregiverPayout) || 0;
    let updatedPayoutCents = Math.round(updatedPayout * 100);

    if (startDt && endDt) {
      const scheduledEndMs = endDt.getTime();
      const scheduledStartMs = startDt.getTime();
      const diffEndMs = scheduledEndMs - nowMs;
      const minutesBeforeEnd = Math.floor(diffEndMs / 60000);

      // Si el cuidador sale más de 15 minutos antes de la hora prevista de fin
      if (minutesBeforeEnd > 15) {
        isEarlyCheckOut = true;
        minutesEarly = minutesBeforeEnd;

        const totalTheoreticalMinutes = Math.max(1, Math.round((scheduledEndMs - scheduledStartMs) / 60000));
        const checkInMs = booking.checkInTime ? booking.checkInTime.toDate().getTime() : scheduledStartMs;
        const actualStartMs = Math.max(scheduledStartMs, checkInMs);
        const actualWorkedMinutes = Math.max(0, Math.min(totalTheoreticalMinutes, Math.round((nowMs - actualStartMs) / 60000)));

        const workedCostCents = Math.min(
          originalCostCents,
          Math.max(0, Math.round((originalCostCents * actualWorkedMinutes) / totalTheoreticalMinutes))
        );
        earlyRefundCents = Math.max(0, originalCostCents - workedCostCents);
        const commissionRate = Number(booking.caregiverCommissionRate) || 0.18;
        const updatedCommissionCents = Math.round(workedCostCents * commissionRate);
        updatedPayoutCents = Math.max(0, workedCostCents - updatedCommissionCents);

        earlyRefundAmount = earlyRefundCents / 100;
        updatedCost = workedCostCents / 100;
        updatedCommission = updatedCommissionCents / 100;
        updatedPayout = updatedPayoutCents / 100;

        // Devolución inmediata del dinero restante al cliente (sin silenciar errores de Stripe)
        if (earlyRefundCents > 0) {
          if (!booking.paymentIntentId) {
            throw new functions.https.HttpsError(
              "failed-precondition",
              "No se encontró el PaymentIntent asociado para procesar el reembolso por salida anticipada."
            );
          }
          await createIdempotentRefund(stripe, {
            paymentIntentId: booking.paymentIntentId,
            amountInCents: earlyRefundCents,
            idempotencyKey: `early_checkout_refund_${bookingId}`,
          });
        }
      }
    }

    const updatePayload = {
      checkOutTime: admin.firestore.FieldValue.serverTimestamp(),
      liveStatus: "completed",
      status: "completed",
      careNotes: careNotes,
      isEarlyCheckOut,
      escrowLock: admin.firestore.FieldValue.delete(),
    };

    if (isEarlyCheckOut) {
      updatePayload.minutesEarlyCheckOut = minutesEarly;
      updatePayload.earlyCheckOutRefunded = true;
      updatePayload.earlyCheckOutRefundAmountCents = earlyRefundCents;
      updatePayload.earlyCheckOutRefundAmount = earlyRefundAmount;
      updatePayload.originalCostCents = originalCostCents;
      updatePayload.cost = updatedCost;
      updatePayload.caregiverCommissionAmount = updatedCommission;
      updatePayload.caregiverPayout = updatedPayout;
      updatePayload.escrowStatus = updatedPayoutCents === 0
        ? "refunded"
        : (booking.escrowStatus === "held" ? "held" : (booking.escrowStatus || "held"));
    }

    await bookingRef.update(updatePayload);
    lockAcquired = false;

    if (isEarlyCheckOut && updatedPayoutCents === 0) {
      await syncCaregiverClientAccess(booking.clientId, booking.caregiverId);
    }

    // Notificar a la familia
    await sendPushNotification(
      booking.clientId,
      "Servicio finalizado",
      isEarlyCheckOut
        ? `${booking.caregiverName || "El cuidador"} ha finalizado la salida con ${minutesEarly} min de antelación. Se ha reembolsado la parte no trabajada.`
        : `${booking.caregiverName || "El cuidador"} ha completado el turno y registrado el resumen del día.`,
      { type: "booking", bookingId, senderId: uid },
      { excludeUserIds: [uid] }
    );

    return {
      success: true,
      isEarlyCheckOut,
      minutesEarly,
      refundAmount: earlyRefundAmount,
      newPayout: updatedPayout,
    };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error(`Error in recordBookingCheckOut for ${bookingId}:`, error);
    throw new functions.https.HttpsError("internal", "No se pudo registrar la salida en este momento. Inténtalo de nuevo.");
  } finally {
    if (lockAcquired) await releaseEscrowLock(bookingRef);
  }
});

exports.cancelPendingCheckout = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  const uid = context.auth.uid;
  const bookingIds = Array.isArray(data?.bookingIds)
    ? [...new Set(data.bookingIds.map((id) => String(id).trim()).filter(Boolean))]
    : [];
  if (bookingIds.length === 0) return { success: true, cleaned: 0 };

  const stripe = require("stripe")(stripeSecret.value());
  const db = admin.firestore();
  const cancelledIntents = new Set();
  const expiredSessions = new Set();
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
    if (b.status !== "pendingPayment" || b.paymentStatus === "paid" || b.paymentStatus === "processing") {
      continue;
    }
    if (b.checkoutSessionId && !expiredSessions.has(b.checkoutSessionId)) {
      expiredSessions.add(b.checkoutSessionId);
      await stripe.checkout.sessions.expire(b.checkoutSessionId).catch(() => {});
    }
    if (b.paymentIntentId && !cancelledIntents.has(b.paymentIntentId)) {
      cancelledIntents.add(b.paymentIntentId);
      try {
        const pi = await stripe.paymentIntents.retrieve(b.paymentIntentId);
        if (pi && ["requires_payment_method", "requires_confirmation", "requires_action", "requires_capture"].includes(pi.status)) {
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
      if (!["held", "pending", "payout_blocked"].includes(booking.escrowStatus)) {
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

    const amountInCents = Math.round((Number(booking.caregiverPayout) || 0) * 100);
    if (amountInCents <= 0) {
      throw new functions.https.HttpsError("failed-precondition", "El importe a transferir no es válido.");
    }

    const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
    const connectCheck = await checkCaregiverConnectReadiness(stripe, caregiverDoc);
    if (!connectCheck.ready) {
      await bookingRef.update({
        escrowStatus: "payout_blocked",
        escrowLock: admin.firestore.FieldValue.delete(),
      });
      lockAcquired = false;
      await db.collection("admin_alerts").add({
        type: "payout_blocked_connect_not_ready",
        severity: "urgent",
        bookingId,
        caregiverId: booking.caregiverId || null,
        clientId: booking.clientId || null,
        payoutAmountCents: amountInCents,
        reason: `Caregiver Connect not ready during releaseEscrowPayment: ${connectCheck.reason}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new functions.https.HttpsError("failed-precondition", "La cuenta de cobros del cuidador no está habilitada para transferencias. El pago ha quedado retenido de forma segura.");
    }

    const transfer = await createLinkedStripeTransfer(stripe, {
      amountInCents,
      destination: connectCheck.accountId,
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
    throw new functions.https.HttpsError("internal", "No se pudo liberar el pago en custodia. Inténtalo más tarde.");
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
      if (["disputed", "stripe_disputed"].includes(booking.escrowStatus) && !callerIsAdmin) {
        throw new functions.https.HttpsError("failed-precondition", "No se puede cancelar una reserva con una disputa abierta. Espera a su resolución.");
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
    if (!isPaid) {
      if (booking.checkoutSessionId) {
        await stripe.checkout.sessions.expire(booking.checkoutSessionId).catch(() => {});
      }
      if (booking.paymentIntentId) {
        try {
          const openPi = await stripe.paymentIntents.retrieve(booking.paymentIntentId);
          if (openPi && ["requires_payment_method", "requires_confirmation", "requires_action", "requires_capture"].includes(openPi.status)) {
            await stripe.paymentIntents.cancel(booking.paymentIntentId);
          }
        } catch (_) {}
      }
    }

    const costCents = Math.round((Number(booking.cost) || 0) * 100);
    const totalPaidCents = Math.round((Number(booking.totalPaid) || 0) * 100);

    if (callerIsCaregiver || booking.status === "pending" || booking.status === "pendingPayment") {
      if (isPaid && booking.paymentIntentId && totalPaidCents > 0) {
        await createIdempotentRefund(stripe, {
          paymentIntentId: booking.paymentIntentId,
          amountInCents: totalPaidCents,
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
      const managementFeeCents = Math.max(100, Math.round(costCents * 0.05));
      const refundAmountCents = Math.max(0, totalPaidCents - managementFeeCents);

      if (isPaid && booking.paymentIntentId && refundAmountCents > 0) {
        await createIdempotentRefund(stripe, {
          paymentIntentId: booking.paymentIntentId,
          amountInCents: refundAmountCents,
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
    const refundAmountCents = Math.round(costCents * 0.45);
    const caregiverPayoutCents = Math.round(costCents * 0.45);

    if (booking.paymentIntentId && refundAmountCents > 0) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: refundAmountCents,
        idempotencyKey: `late_cancel_refund_${bookingId}`,
      });
    }
    const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
    const connectCheck = await checkCaregiverConnectReadiness(stripe, caregiverDoc);
    let nextEscrowStatus = "resolved_partial";

    if (caregiverPayoutCents > 0) {
      if (connectCheck.ready && (booking.paymentIntentId || booking.transferGroup)) {
        await createLinkedStripeTransfer(stripe, {
          amountInCents: caregiverPayoutCents,
          destination: connectCheck.accountId,
          paymentIntentId: booking.paymentIntentId,
          transferGroup: booking.transferGroup,
          idempotencyKey: `late_cancel_transfer_${bookingId}`,
        });
      } else {
        nextEscrowStatus = "payout_blocked";
        await db.collection("admin_alerts").add({
          type: "payout_blocked_connect_not_ready",
          severity: "urgent",
          bookingId,
          caregiverId: booking.caregiverId || null,
          clientId: booking.clientId || null,
          payoutAmountCents: caregiverPayoutCents,
          reason: `Caregiver Connect not ready during late cancelBookingProcess: ${connectCheck.reason || "missing_payment_link"}`,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    await bookingRef.update({
      status: "cancelledLate",
      escrowStatus: nextEscrowStatus,
      caregiverPayout: caregiverPayoutCents / 100,
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
    console.error("Error in cancelBookingProcess:", error);
    throw new functions.https.HttpsError("internal", "No se pudo completar la cancelación de la reserva.");
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
      if (booking.status !== "pending") {
        throw new functions.https.HttpsError("failed-precondition", "Solo se pueden rechazar reservas en estado pendiente de aceptación.");
      }
      if (booking.checkInTime) {
        throw new functions.https.HttpsError("failed-precondition", "No se puede rechazar una reserva que ya tiene Check-in.");
      }
      if (["disputed", "stripe_disputed"].includes(booking.escrowStatus)) {
        throw new functions.https.HttpsError("failed-precondition", "No se puede rechazar una reserva con una disputa activa.");
      }
      return {};
    });
    lockAcquired = lockResult.acquired;
    const booking = lockResult.booking;

    const isPaid = await verifyPaymentIntentIsPaid(stripe, booking);
    const refundAmountCents = Math.round((Number(booking.totalPaid) || 0) * 100);
    if (isPaid && booking.paymentIntentId && refundAmountCents > 0) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: refundAmountCents,
        idempotencyKey: `reject_refund_${bookingId}`,
      });
    } else if (!isPaid && booking.paymentIntentId) {
      try {
        const openPi = await stripe.paymentIntents.retrieve(booking.paymentIntentId);
        if (openPi && ["requires_payment_method", "requires_confirmation", "requires_action", "requires_capture"].includes(openPi.status)) {
          await stripe.paymentIntents.cancel(booking.paymentIntentId);
        }
      } catch (_) {}
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
    console.error("Error in caregiverRejectBooking:", error);
    throw new functions.https.HttpsError("internal", "No se pudo rechazar la reserva en este momento.");
  } finally {
    if (lockAcquired) await releaseEscrowLock(bookingRef);
  }
});

/**
 * Cancela por No-Show una reserva confirmada cuyo horario ha terminado sin check-in,
 * emite el reembolso íntegro en Stripe, registra incidencia al cuidador y reabre franjas.
 * Devuelve true si liberó escrowLock dentro de la actualización.
 */
async function settleNoShowBooking(stripe, doc, b) {
  const fullRefundCents = Math.round((Number(b.totalPaid) || Number(b.cost) || 0) * 100);
  if (b.paymentIntentId && fullRefundCents > 0) {
    await createIdempotentRefund(stripe, {
      paymentIntentId: b.paymentIntentId,
      amountInCents: fullRefundCents,
      idempotencyKey: `noshow_refund_${doc.id}`,
    });
  }
  await doc.ref.update({
    status: "cancelledLate",
    escrowStatus: "refunded",
    cancellationReason: "No-Show: el cuidador no llegó antes de finalizar el horario",
    cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    escrowLock: admin.firestore.FieldValue.delete(),
  });
  await Promise.all([
    addIncidentToCaregiver(b.caregiverId),
    reopenBookingSlots(b.caregiverId, b.day, b.slot),
    syncCaregiverClientAccess(b.clientId, b.caregiverId),
  ]);
  return true;
}

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

        let pi = null;
        if (hb.paymentIntentId) {
          try {
            pi = await stripe.paymentIntents.retrieve(hb.paymentIntentId, { expand: ["latest_charge"] });
          } catch (_) {}
        } else if (hb.checkoutSessionId) {
          try {
            const cs = await stripe.checkout.sessions.retrieve(hb.checkoutSessionId, { expand: ["payment_intent.latest_charge"] });
            if (cs && cs.payment_intent && typeof cs.payment_intent === "object") {
              pi = cs.payment_intent;
            }
          } catch (_) {}
        }

        if (pi && (pi.status === "succeeded" || pi.status === "processing")) {
          const isOfferBooking = Boolean(hb.offerId || hb.isJobOffer);
          const nextStatus = isOfferBooking ? "confirmed" : "pending";
          const isPaidNow = pi.status === "succeeded";
          await holdDoc.ref.update({
            status: nextStatus,
            paymentStatus: isPaidNow ? "paid" : "processing",
            escrowStatus: "held",
            paymentIntentId: pi.id,
            paymentMethodType: extractStripePaymentMethodType(pi),
            escrowLock: admin.firestore.FieldValue.delete(),
          });
          lockAcquired = false;
          if (isOfferBooking && hb.offerId) {
            await acceptJobOfferOnPayment(db, {
              offerId: hb.offerId,
              applicationId: hb.applicationId,
              caregiverId: hb.caregiverId,
            });
          }
          if (nextStatus === "confirmed" && isPaidNow) {
            await syncCaregiverClientAccess(hb.clientId, hb.caregiverId);
          }
          continue;
        }

        if (hb.checkoutSessionId) {
          await stripe.checkout.sessions.expire(hb.checkoutSessionId).catch(() => {});
        }
        if (pi && ["requires_payment_method", "requires_confirmation", "requires_action", "requires_capture"].includes(pi.status)) {
          await stripe.paymentIntents.cancel(pi.id).catch(() => {});
        }

        await reopenBookingSlots(hb.caregiverId, hb.day, hb.slot);
        await holdDoc.ref.update({
          status: "expired",
          paymentStatus: "expired",
          escrowStatus: "cancelled",
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          escrowLock: admin.firestore.FieldValue.delete(),
        });
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
        const fullRefundCents = Math.round((Number(pb.totalPaid) || Number(pb.cost) || 0) * 100);
        if (isPaid && pb.paymentIntentId && fullRefundCents > 0) {
          await createIdempotentRefund(stripe, {
            paymentIntentId: pb.paymentIntentId,
            amountInCents: fullRefundCents,
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

  // 1. Manejo de reservas normales (24h tras fin teórico) y No-Shows (inmediato al fin teórico)
  try {
    const snapshot = await db.collection("bookings")
      .where("escrowStatus", "==", "held")
      .where("status", "in", ["confirmed", "completed"])
      .get();
    
    for (const doc of snapshot.docs) {
      let lockAcquired = false;
      try {
        const lockRes = await acquireEscrowLock(doc.ref, "cronAutoRelease", async (b) => {
          if (b.escrowStatus !== "held" || !["confirmed", "completed"].includes(b.status)) return { skip: true };
          const theoreticalStartTime = parseBookingStartDateTime(b.day, b.slot);
          const theoreticalEndTime = parseBookingEndDateTime(b.day, b.slot);
          if (!theoreticalStartTime || !theoreticalEndTime) return { skip: true };
          if (!b.checkInTime) {
            if (now.getTime() < theoreticalEndTime.getTime()) return { skip: true };
            return {};
          }
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
          // NO-SHOW: Cancelación inmediata al finalizar la hora prevista (reembolso íntegro al cliente)
          await settleNoShowBooking(stripe, doc, b);
          lockAcquired = false;
        } else {
          // CHECKED IN: Evaluar si llegó tarde (solo si no fue ya prorrateado y reembolsado en recordBookingCheckOut)
          const checkInDate = b.checkInTime.toDate();
          const totalTheoreticalMinutes = Math.max(1, Math.round((theoreticalEndTime.getTime() - theoreticalStartTime.getTime()) / 60000));
          const minutesLate = (checkInDate.getTime() - theoreticalStartTime.getTime()) / 60000;
          const alreadyProratedByEarlyCheckOut = b.earlyCheckOutRefunded === true;

          if (!alreadyProratedByEarlyCheckOut && minutesLate > 15) {
            const originalCostCents = Math.round((Number(b.cost) || 0) * 100);
            const workedMinutes = Math.max(0, Math.min(totalTheoreticalMinutes, Math.round(totalTheoreticalMinutes - minutesLate)));
            const newCostCents = Math.min(
              originalCostCents,
              Math.max(0, Math.round((originalCostCents * workedMinutes) / totalTheoreticalMinutes))
            );
            const amountToRefundCents = Math.max(0, originalCostCents - newCostCents);
            const commRate = Number(b.caregiverCommissionRate) || 0.18;
            const newCommissionCents = Math.round(newCostCents * commRate);
            const newPayoutCents = Math.max(0, newCostCents - newCommissionCents);

            if (b.paymentIntentId && amountToRefundCents > 0) {
              await createIdempotentRefund(stripe, {
                paymentIntentId: b.paymentIntentId,
                amountInCents: amountToRefundCents,
                idempotencyKey: `late_checkin_refund_${doc.id}`,
              });
            }

            const caregiverDoc = await db.collection("caregivers").doc(b.caregiverId).get();
            const connectCheck = await checkCaregiverConnectReadiness(stripe, caregiverDoc);
            let nextEscrowStatus = "released_partial";

            if (newPayoutCents > 0) {
              if (connectCheck.ready && (b.paymentIntentId || b.transferGroup)) {
                await createLinkedStripeTransfer(stripe, {
                  amountInCents: newPayoutCents,
                  destination: connectCheck.accountId,
                  paymentIntentId: b.paymentIntentId,
                  transferGroup: b.transferGroup,
                  idempotencyKey: `late_checkin_transfer_${doc.id}`,
                });
              } else {
                nextEscrowStatus = "payout_blocked";
                await db.collection("admin_alerts").add({
                  type: "payout_blocked_connect_not_ready",
                  severity: "urgent",
                  bookingId: doc.id,
                  caregiverId: b.caregiverId || null,
                  clientId: b.clientId || null,
                  payoutAmountCents: newPayoutCents,
                  reason: `Caregiver Connect not ready during autoReleaseEscrowCron (late check-in): ${connectCheck.reason || "missing_payment_link"}`,
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
              }
            }

            await doc.ref.update({
              status: "completed",
              escrowStatus: nextEscrowStatus,
              paymentStatus: "paid",
              caregiverPayout: newPayoutCents / 100,
              caregiverCommissionAmount: newCommissionCents / 100,
              cost: newCostCents / 100,
              escrowLock: admin.firestore.FieldValue.delete(),
            });
            lockAcquired = false;
            if (nextEscrowStatus !== "payout_blocked") {
              await Promise.all([
                addCompletedHours(b.clientId, b.caregiverId, b.slot),
                syncCaregiverClientAccess(b.clientId, b.caregiverId),
              ]);
            }
          } else {
            const payoutCents = Math.round((Number(b.caregiverPayout) || 0) * 100);
            const caregiverDoc = await db.collection("caregivers").doc(b.caregiverId).get();
            const connectCheck = await checkCaregiverConnectReadiness(stripe, caregiverDoc);
            let nextEscrowStatus = alreadyProratedByEarlyCheckOut ? "released_partial" : "released_auto";

            if (payoutCents > 0) {
              if (connectCheck.ready && (b.paymentIntentId || b.transferGroup)) {
                await createLinkedStripeTransfer(stripe, {
                  amountInCents: payoutCents,
                  destination: connectCheck.accountId,
                  paymentIntentId: b.paymentIntentId,
                  transferGroup: b.transferGroup,
                  idempotencyKey: `auto_release_${doc.id}`,
                });
              } else {
                nextEscrowStatus = "payout_blocked";
                await db.collection("admin_alerts").add({
                  type: "payout_blocked_connect_not_ready",
                  severity: "urgent",
                  bookingId: doc.id,
                  caregiverId: b.caregiverId || null,
                  clientId: b.clientId || null,
                  payoutAmountCents: payoutCents,
                  reason: `Caregiver Connect not ready during autoReleaseEscrowCron: ${connectCheck.reason || "missing_payment_link"}`,
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
              }
            }

            await doc.ref.update({
              status: "completed",
              escrowStatus: nextEscrowStatus,
              paymentStatus: "paid",
              escrowLock: admin.firestore.FieldValue.delete(),
            });
            lockAcquired = false;
            if (nextEscrowStatus !== "payout_blocked") {
              await Promise.all([
                addCompletedHours(b.clientId, b.caregiverId, b.slot),
                syncCaregiverClientAccess(b.clientId, b.caregiverId),
              ]);
            }
          }
        }
      } catch (e) {
        console.error("Cron Error processing booking", doc.id, e);
      } finally {
        if (lockAcquired) await releaseEscrowLock(doc.ref);
      }
    }
  } catch (releaseCronErr) {
    console.error("Cron Error querying held confirmed/completed bookings:", releaseCronErr.message);
  }
  
  // 2. Manejo de Disputas ignoradas por el cuidador > 24 horas
  try {
    const disputes = await db.collection("bookings")
      .where("escrowStatus", "==", "disputed").get();
      
    for (const doc of disputes.docs) {
      if (doc.data()?.disputeEscalated === true) continue;
      let lockAcquired = false;
      try {
        const lockRes = await acquireEscrowLock(doc.ref, "cronDisputeTimeout", async (b) => {
          if (b.escrowStatus !== "disputed" || b.disputeEscalated === true) return { skip: true };
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
        const alreadyRefundedCents = Math.max(0, Math.round(Number(b.earlyCheckOutRefundAmountCents || b.refundedAmountCents || 0)));
        const totalChargedCents = Math.round((Number(b.totalPaid) || Number(b.cost) || 0) * 100);
        const disputeRefundCents = Math.max(0, totalChargedCents - alreadyRefundedCents);
        if (b.paymentIntentId && disputeRefundCents > 0) {
          await createIdempotentRefund(stripe, {
            paymentIntentId: b.paymentIntentId,
            amountInCents: disputeRefundCents,
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
        const alreadyRefundedCents = Math.max(0, Math.round(Number(b.earlyCheckOutRefundAmountCents || b.refundedAmountCents || 0)));
        const totalChargedCents = Math.round((Number(b.totalPaid) || Number(b.cost) || 0) * 100);
        const legacyRefundCents = Math.max(0, totalChargedCents - alreadyRefundedCents);
        if (b.paymentIntentId && legacyRefundCents > 0) {
          await createIdempotentRefund(stripe, {
            paymentIntentId: b.paymentIntentId,
            amountInCents: legacyRefundCents,
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

  // 4. Mantenimiento automático de ofertas de empleo (urgencia a las 24h sin solicitudes y cierre al llegar la reserva)
  try {
    const openOffersSnap = await db.collection("job_offers").where("status", "==", "open").get();
    const twentyFourHoursMs = 24 * 60 * 60 * 1000;
    for (const offerDoc of openOffersSnap.docs) {
      try {
        const offer = offerDoc.data() || {};
        if (offer.isUrgent === true) continue;
        const startDate = offer.startDate?.toDate ? offer.startDate.toDate() : null;
        if (!startDate || startDate <= now) continue;
        const createdAt = offer.createdAt?.toDate ? offer.createdAt.toDate() : null;
        const elapsedSinceCreated = createdAt ? (now.getTime() - createdAt.getTime()) : 0;
        const timeUntilStart = startDate.getTime() - now.getTime();
        if (elapsedSinceCreated >= twentyFourHoursMs || timeUntilStart < twentyFourHoursMs) {
          const appsSnap = await offerDoc.ref.collection("applications").limit(1).get();
          if (appsSnap.empty) {
            await offerDoc.ref.update({
              isUrgent: true,
              urgentPromotedByServer: true,
              urgencyBonusRate: 0.10,
              applicationsCount: 0,
            });
          }
        }
      } catch (offerErr) {
        console.warn(`Cron error checking open offer ${offerDoc.id}:`, offerErr.message);
      }
    }

    const inProgressOffersSnap = await db.collection("job_offers").where("status", "==", "inProgress").get();
    for (const offerDoc of inProgressOffersSnap.docs) {
      try {
        const offer = offerDoc.data() || {};
        const startDate = offer.startDate?.toDate ? offer.startDate.toDate() : null;
        if (startDate && startDate <= now) {
          await offerDoc.ref.update({ status: "completed" });
        }
      } catch (offerErr) {
        console.warn(`Cron error completing inProgress offer ${offerDoc.id}:`, offerErr.message);
      }
    }
  } catch (offersCronErr) {
    console.warn("Cron error maintaining job_offers:", offersCronErr.message);
  }
  
  return null;
});

/**
 * Monitoriza cada 5 minutos las reservas confirmadas cuya hora de inicio ya ha pasado
 * sin check-in del cuidador:
 * - Si sigue dentro de la franja y aún no se avisó: notifica al cuidador de su retraso y del
 *   margen de cortesía de 15 minutos antes de la penalización económica.
 * - Si ya alcanzó o superó la hora de finalización sin fichaje: cancela por No-Show al instante
 *   con reembolso íntegro al cliente e incidencia al cuidador.
 */
exports.monitorLateBookingsCron = functions.region("europe-west1").runWith({ secrets: [stripeSecret] }).pubsub.schedule("every 5 minutes").onRun(async () => {
  const stripe = require("stripe")(stripeSecret.value());
  const db = admin.firestore();
  const now = new Date();
  const nowMs = now.getTime();
  const graceMs = 15 * 60 * 1000;

  try {
    const snapshot = await db
      .collection("bookings")
      .where("escrowStatus", "==", "held")
      .where("status", "==", "confirmed")
      .get();

    for (const doc of snapshot.docs) {
      const raw = doc.data() || {};
      if (raw.checkInTime) continue;

      const startDt = parseBookingStartDateTime(raw.day, raw.slot);
      const endDt = parseBookingEndDateTime(raw.day, raw.slot);
      if (!startDt || !endDt) continue;

      if (nowMs >= endDt.getTime()) {
        let lockAcquired = false;
        try {
          const lockRes = await acquireEscrowLock(doc.ref, "cronNoShowCancel", async (b) => {
            if (b.escrowStatus !== "held" || b.status !== "confirmed" || b.checkInTime) {
              return { skip: true };
            }
            const lockedEnd = parseBookingEndDateTime(b.day, b.slot);
            if (!lockedEnd || nowMs < lockedEnd.getTime()) return { skip: true };
            return {};
          });
          if (!lockRes.acquired) continue;
          lockAcquired = true;
          const b = lockRes.booking;

          const isPaid = await verifyPaymentIntentIsPaid(stripe, b);
          if (!isPaid) continue;

          await settleNoShowBooking(stripe, doc, b);
          lockAcquired = false;
        } catch (noShowErr) {
          console.error("monitorLateBookingsCron No-Show error:", doc.id, noShowErr);
        } finally {
          if (lockAcquired) await releaseEscrowLock(doc.ref);
        }
        continue;
      }

      if (nowMs > startDt.getTime() && !raw.lateNotificationSentAt && raw.caregiverId) {
        try {
          const claimed = await db.runTransaction(async (tx) => {
            const snap = await tx.get(doc.ref);
            if (!snap.exists) return false;
            const current = snap.data() || {};
            if (
              current.status !== "confirmed" ||
              current.escrowStatus !== "held" ||
              current.checkInTime ||
              current.lateNotificationSentAt
            ) {
              return false;
            }
            tx.update(doc.ref, {
              lateNotificationSentAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return true;
          });

          if (claimed) {
            const graceDeadlineMs = startDt.getTime() + graceMs;
            const graceCutoffStr = new Intl.DateTimeFormat("es-ES", {
              timeZone: "Europe/Madrid",
              hour: "2-digit",
              minute: "2-digit",
            }).format(new Date(graceDeadlineMs));

            const body = nowMs <= graceDeadlineMs
              ? `Ya ha empezado tu reserva del ${formatDateEs(raw.day)} (${raw.slot}). Si no fichas antes de las ${graceCutoffStr} (15 min de margen) tendrás una penalización económica, y si no llegas antes del fin se cancelará.`
              : `Llevas más de 15 minutos de retraso en tu reserva del ${formatDateEs(raw.day)} (${raw.slot}) y aplica penalización económica por minuto. Ficha cuanto antes o la reserva se cancelará al finalizar el horario.`;

            await sendPushNotification(
              raw.caregiverId,
              "⏰ Estás llegando tarde al servicio",
              body,
              { type: "booking", bookingId: doc.id, senderId: raw.clientId || "" },
              { excludeUserIds: raw.clientId ? [raw.clientId] : [] }
            );
          }
        } catch (lateWarnErr) {
          console.warn("monitorLateBookingsCron late warning error:", doc.id, lateWarnErr.message);
        }
      }
    }

    // Monitorización de Check-out para cuidadores que hicieron Check-in:
    // El cuidador tiene hasta 15 minutos después de la finalización de la reserva para fichar la salida.
    // Pasados 15 minutos tras el fin del servicio:
    // 1) Se envía notificación push de que debe hacer el check-out de inmediato.
    // 2) Si sigue sin fichar la salida pasado un margen adicional (p. ej. 30 minutos tras el fin del servicio),
    //    se le anota una falta y se le penaliza con una incidencia leve (5 incidencias leves = 1 normal).
    const activeCheckIns = await db
      .collection("bookings")
      .where("status", "==", "confirmed")
      .get();

    for (const doc of activeCheckIns.docs) {
      const b = doc.data() || {};
      if (!b.checkInTime || b.checkOutTime) continue;

      const endDt = parseBookingEndDateTime(b.day, b.slot);
      if (!endDt) continue;

      const endMs = endDt.getTime();
      const fifteenMinAfterEnd = endMs + (15 * 60 * 1000);
      const penaltyDeadline = endMs + (30 * 60 * 1000);

      // Si han pasado más de 15 minutos desde el fin y no se le ha enviado aviso de check-out
      if (nowMs > fifteenMinAfterEnd && !b.checkOutReminderSentAt && b.caregiverId) {
        try {
          const claimed = await db.runTransaction(async (tx) => {
            const snap = await tx.get(doc.ref);
            if (!snap.exists) return false;
            const cur = snap.data() || {};
            if (!cur.checkInTime || cur.checkOutTime || cur.checkOutReminderSentAt) return false;
            tx.update(doc.ref, {
              checkOutReminderSentAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return true;
          });

          if (claimed) {
            await sendPushNotification(
              b.caregiverId,
              "⏳ Debes registrar la salida (Check-out)",
              `Ha finalizado el horario del servicio del ${formatDateEs(b.day)} (${b.slot}). Debes fichar la salida y escribir el resumen del día en el diario obligatoriamente para evitar una falta.`,
              { type: "booking", bookingId: doc.id, senderId: b.clientId || "" },
              { excludeUserIds: b.clientId ? [b.clientId] : [] }
            );
          }
        } catch (warnErr) {
          console.warn(`Error sending checkout reminder for ${doc.id}:`, warnErr.message);
        }
      }

      // Si han pasado más de 30 minutos desde el fin y sigue sin fichar la salida, penalizar con incidencia leve
      if (nowMs > penaltyDeadline && !b.missingCheckOutPenalizedAt && b.caregiverId) {
        let lockAcquired = false;
        try {
          const lockRes = await acquireEscrowLock(doc.ref, "cronMissingCheckOutPenalty", async (cur) => {
            if (!cur.checkInTime || cur.checkOutTime || cur.missingCheckOutPenalizedAt) {
              return { skip: true };
            }
            return {};
          });

          if (lockRes.acquired) {
            lockAcquired = true;
            await doc.ref.update({
              missingCheckOutPenalizedAt: admin.firestore.FieldValue.serverTimestamp(),
              hasMissingCheckOutFault: true,
              escrowLock: admin.firestore.FieldValue.delete(),
            });
            lockAcquired = false;

            await addMinorIncidentToCaregiver(
              b.caregiverId,
              `Falta de check-out en la reserva del ${b.day} (${b.slot})`
            );

            await sendPushNotification(
              b.caregiverId,
              "⚠️ Incidencia leve por falta de Check-out",
              `No registraste la salida del servicio del ${formatDateEs(b.day)} dentro del plazo. Se ha anotado una falta e incidencia leve en tu perfil (5 incidencias leves equivalen a 1 normal y restan puntos en las búsquedas).`,
              { type: "booking", bookingId: doc.id, senderId: b.clientId || "" },
              { excludeUserIds: b.clientId ? [b.clientId] : [] }
            );
          }
        } catch (penErr) {
          console.error(`Error penalizing missing check-out for ${doc.id}:`, penErr);
        } finally {
          if (lockAcquired) await releaseEscrowLock(doc.ref);
        }
      }
    }
  } catch (err) {
    console.error("monitorLateBookingsCron query error:", err.message);
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
  const refundToClientCents = Math.round(refundToClient * 100);
  const payoutToCaregiverCents = Math.round(payoutToCaregiver * 100);

  const db = admin.firestore();
  const bookingRef = db.collection("bookings").doc(bookingId);
  let lockAcquired = false;

  try {
    const settledEscrowStatuses = ["released", "released_manual", "released_auto", "resolved_partial", "refunded"];
    const lockResult = await acquireEscrowLock(bookingRef, "adminResolveDispute", async (booking) => {
      if (settledEscrowStatuses.includes(booking.escrowStatus)) {
        throw new functions.https.HttpsError("failed-precondition", "Esta reserva ya fue liquidada anteriormente.");
      }
      const alreadyRefundedCents = Math.max(0, Math.round(Number(booking.earlyCheckOutRefundAmountCents || booking.refundedAmountCents || 0)));
      const totalChargedCents = Math.round((Number(booking.totalPaid) || Number(booking.cost) || 0) * 100);
      const maxAllowedCents = Math.max(0, totalChargedCents - alreadyRefundedCents);
      if (refundToClientCents + payoutToCaregiverCents > maxAllowedCents) {
        throw new functions.https.HttpsError("invalid-argument", "La suma de reembolso y pago al cuidador supera el total abonado disponible.");
      }
      return {};
    });
    lockAcquired = lockResult.acquired;
    const booking = lockResult.booking;

    const isPaid = await verifyPaymentIntentIsPaid(stripe, booking);
    if (!isPaid && (refundToClientCents > 0 || payoutToCaregiverCents > 0)) {
      throw new functions.https.HttpsError("failed-precondition", "El PaymentIntent asociado aún no está cobrado en Stripe.");
    }

    let caregiverStripeAccountId = "";
    if (payoutToCaregiverCents > 0) {
      const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
      const connectCheck = await checkCaregiverConnectReadiness(stripe, caregiverDoc);
      if (!connectCheck.ready) {
        await bookingRef.update({
          escrowStatus: "payout_blocked",
          escrowLock: admin.firestore.FieldValue.delete(),
        });
        lockAcquired = false;
        await db.collection("admin_alerts").add({
          type: "payout_blocked_connect_not_ready",
          severity: "urgent",
          bookingId,
          caregiverId: booking.caregiverId || null,
          clientId: booking.clientId || null,
          payoutAmountCents: payoutToCaregiverCents,
          reason: `Caregiver Connect not ready during adminResolveDispute: ${connectCheck.reason}`,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        throw new functions.https.HttpsError("failed-precondition", "La cuenta de Stripe Connect del cuidador no está habilitada para transferencias. El pago quedó marcado como payout_blocked.");
      }
      caregiverStripeAccountId = connectCheck.accountId;
    }
    
    if (refundToClientCents > 0 && booking.paymentIntentId) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: refundToClientCents,
        idempotencyKey: `admin_dispute_refund_${bookingId}`,
      });
    }
    
    if (payoutToCaregiverCents > 0 && (booking.paymentIntentId || booking.transferGroup)) {
      await createLinkedStripeTransfer(stripe, {
        amountInCents: payoutToCaregiverCents,
        destination: caregiverStripeAccountId,
        paymentIntentId: booking.paymentIntentId,
        transferGroup: booking.transferGroup,
        idempotencyKey: `admin_dispute_transfer_${bookingId}`,
      });
    }
    
    const resolvedEscrowStatus = payoutToCaregiverCents === 0 && refundToClientCents > 0 ? "refunded" : "resolved_partial";
    const costCents = Math.round((Number(booking.cost) || 0) * 100);
    const remainingCommissionCents = Math.max(0, costCents - refundToClientCents - payoutToCaregiverCents);
    await bookingRef.update({
      escrowStatus: resolvedEscrowStatus,
      status: "completed",
      disputeRequested: false,
      caregiverPayout: payoutToCaregiverCents / 100,
      caregiverCommissionAmount: remainingCommissionCents / 100,
      escrowLock: admin.firestore.FieldValue.delete(),
    });
    lockAcquired = false;
    
    if (payoutToCaregiverCents > 0) {
      await addCompletedHours(booking.clientId, booking.caregiverId, booking.slot);
    } else if (refundToClientCents > 0 && booking.caregiverId) {
      await addIncidentToCaregiver(booking.caregiverId);
    }
    await syncCaregiverClientAccess(booking.clientId, booking.caregiverId);
    
    return { success: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Error in adminResolveDispute:", error);
    throw new functions.https.HttpsError("internal", "No se pudo resolver la disputa en este momento.");
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
      if (booking.caregiverId !== context.auth.uid && !callerIsAdmin) {
        throw new functions.https.HttpsError("permission-denied", "Solo el cuidador asignado o un administrador puede aceptar la propuesta de disputa.");
      }
      if (booking.escrowStatus !== "disputed") {
        throw new functions.https.HttpsError("failed-precondition", "La reserva no tiene una disputa abierta activa.");
      }
      const costCents = Math.round((Number(booking.cost) || 0) * 100);
      const proposedRefundCents = Math.round((Number(booking.disputeAmount) || 0) * 100);
      if (!Number.isFinite(proposedRefundCents) || proposedRefundCents <= 0 || proposedRefundCents > costCents) {
        throw new functions.https.HttpsError("failed-precondition", "El importe propuesto de disputa no es válido.");
      }
      return {};
    });
    lockAcquired = lockResult.acquired;
    const booking = lockResult.booking;
    const costCents = Math.round((Number(booking.cost) || 0) * 100);
    const proposedRefundCents = Math.round((Number(booking.disputeAmount) || 0) * 100);

    const isPaid = await verifyPaymentIntentIsPaid(stripe, booking);
    if (!isPaid) {
      throw new functions.https.HttpsError("failed-precondition", "El pago asociado aún no está liquidado en Stripe.");
    }

    const remainingForCaregiverCents = Math.max(0, costCents - proposedRefundCents);
    const commissionRate = (booking.caregiverCommissionRate > 0 && booking.caregiverCommissionRate <= 0.30)
      ? Number(booking.caregiverCommissionRate)
      : 0.18;
    const comisionCuidadorCents = Math.round(remainingForCaregiverCents * commissionRate);
    const payoutCuidadorCents = Math.max(0, remainingForCaregiverCents - comisionCuidadorCents);

    const caregiverDoc = await db.collection("caregivers").doc(booking.caregiverId).get();
    let caregiverStripeAccountId = "";
    if (payoutCuidadorCents > 0) {
      const connectCheck = await checkCaregiverConnectReadiness(stripe, caregiverDoc);
      if (!connectCheck.ready) {
        await bookingRef.update({
          escrowStatus: "payout_blocked",
          escrowLock: admin.firestore.FieldValue.delete(),
        });
        lockAcquired = false;
        await db.collection("admin_alerts").add({
          type: "payout_blocked_connect_not_ready",
          severity: "urgent",
          bookingId,
          caregiverId: booking.caregiverId || null,
          clientId: booking.clientId || null,
          payoutAmountCents: payoutCuidadorCents,
          reason: `Caregiver Connect not ready during processResolutionAgreement: ${connectCheck.reason}`,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        throw new functions.https.HttpsError("failed-precondition", "La cuenta bancaria (Stripe) del cuidador no está habilitada para recibir transferencias.");
      }
      caregiverStripeAccountId = connectCheck.accountId;
    }

    if (booking.paymentIntentId && proposedRefundCents > 0) {
      await createIdempotentRefund(stripe, {
        paymentIntentId: booking.paymentIntentId,
        amountInCents: proposedRefundCents,
        idempotencyKey: `dispute_agree_refund_${bookingId}`,
      });
    }
    
    if (payoutCuidadorCents > 0 && (booking.paymentIntentId || booking.transferGroup)) {
      await createLinkedStripeTransfer(stripe, {
        amountInCents: payoutCuidadorCents,
        destination: caregiverStripeAccountId,
        paymentIntentId: booking.paymentIntentId,
        transferGroup: booking.transferGroup,
        idempotencyKey: `dispute_agree_transfer_${bookingId}`,
      });
    }
    
    await bookingRef.update({
      escrowStatus: payoutCuidadorCents === 0 ? "refunded" : "resolved_partial",
      status: "completed",
      disputeRequested: false,
      caregiverPayout: payoutCuidadorCents / 100,
      caregiverCommissionAmount: comisionCuidadorCents / 100,
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
    console.error("Error in processResolutionAgreement:", error);
    throw new functions.https.HttpsError("internal", "No se pudo procesar el acuerdo de resolución.");
  } finally {
    if (lockAcquired) await releaseEscrowLock(bookingRef);
  }
});

// --- FCM PUSH NOTIFICATIONS TRIGGERS ---

const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");

function haversineDistanceKm(lat1, lon1, lat2, lon2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

async function resolveTargetUserIds(db, targetId) {
  const targetUids = new Set();
  if (!targetId) return targetUids;
  targetUids.add(targetId);

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
  return targetUids;
}

// Función auxiliar para buscar token(s) y enviar notificación push (con soporte multifamiliar y exclusión de emisor)
async function sendPushNotification(targetId, title, body, dataPayload = {}, options = {}) {
  try {
    if (!targetId) return;
    const db = admin.firestore();
    const excludeRawIds = Array.isArray(options?.excludeUserIds)
      ? options.excludeUserIds.filter(Boolean)
      : [];

    const [targetUids, excludedSets] = await Promise.all([
      resolveTargetUserIds(db, targetId),
      Promise.all(excludeRawIds.map((id) => resolveTargetUserIds(db, id))),
    ]);

    const excludedUids = new Set();
    excludedSets.forEach((set) => set.forEach((uid) => excludedUids.add(uid)));
    excludedUids.forEach((uid) => targetUids.delete(uid));

    if (targetUids.size === 0) {
      console.log(`Push omitida para ${targetId}: sin destinatarios tras excluir emisor.`);
      return;
    }

    const [userSnaps, excludedSnaps] = await Promise.all([
      Promise.all([...targetUids].map((uid) => db.collection("users").doc(uid).get())),
      Promise.all([...excludedUids].map((uid) => db.collection("users").doc(uid).get())),
    ]);

    const excludedTokens = new Set(
      excludedSnaps
        .filter((doc) => doc.exists && typeof doc.data()?.fcmToken === "string" && doc.data().fcmToken.trim())
        .map((doc) => doc.data().fcmToken.trim())
    );

    const tokenEntries = [];
    const seenTokens = new Set();
    userSnaps.forEach((doc) => {
      if (!doc.exists) return;
      const rawToken = doc.data()?.fcmToken;
      const token = typeof rawToken === "string" ? rawToken.trim() : "";
      if (!token || excludedTokens.has(token) || seenTokens.has(token)) return;
      seenTokens.add(token);
      tokenEntries.push({ ref: doc.ref, token });
    });

    if (tokenEntries.length === 0) {
      console.log(`Ningún destinatario de ${targetId} tiene fcmToken válido y distinto al emisor.`);
      return;
    }

    const normalizedData = {};
    Object.entries(dataPayload || {}).forEach(([k, v]) => {
      if (v !== undefined && v !== null) normalizedData[k] = String(v);
    });

    await Promise.all(
      tokenEntries.map(async ({ ref, token }) => {
        try {
          await admin.messaging().send({
            token,
            notification: { title, body },
            data: normalizedData,
          });
        } catch (sendErr) {
          const code = sendErr?.code || "";
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            await ref.update({ fcmToken: admin.firestore.FieldValue.delete() }).catch(() => {});
          } else {
            console.warn(`Error enviando push individual a ${ref.id}:`, sendErr?.message || sendErr);
          }
        }
      })
    );
    console.log(`Push enviada con éxito a ${tokenEntries.length} dispositivo(s) para ${targetId}`);
  } catch (error) {
    console.error(`Error enviando push a ${targetId}:`, error);
  }
}

// 0. Limpieza automática de fcmToken duplicado si un mismo dispositivo inicia sesión con otra cuenta
exports.dedupeUserFcmToken = onDocumentWritten({
  document: "users/{userId}",
  region: "europe-west1",
}, async (event) => {
  const after = event.data?.after?.data();
  const token = typeof after?.fcmToken === "string" ? after.fcmToken.trim() : "";
  if (!token) return null;

  const db = admin.firestore();
  const duplicates = await db.collection("users").where("fcmToken", "==", token).get();
  const batch = db.batch();
  let removed = 0;

  duplicates.forEach((doc) => {
    if (doc.id !== event.params.userId) {
      batch.update(doc.ref, {
        fcmToken: admin.firestore.FieldValue.delete(),
      });
      removed++;
    }
  });

  if (removed > 0) {
    await batch.commit();
    console.log(`[dedupeUserFcmToken] Limpiado fcmToken duplicado en ${removed} cuenta(s) al registrar ${event.params.userId}.`);
  }
  return null;
});

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

  await sendPushNotification(
    receiverId,
    notificationTitle,
    pushBody,
    {
      type: "chat",
      chatRoomId: event.params.chatRoomId,
      senderId: senderId,
    },
    { excludeUserIds: [senderId] }
  );
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
  if (!booking.caregiverId || booking.caregiverId === booking.clientId) {
    return null;
  }
  await sendPushNotification(
    booking.caregiverId,
    "¡Nueva Solicitud de Reserva!",
    `Han solicitado tus servicios para el ${formatDateEs(booking.day)} a las ${booking.slot}.`,
    { type: "booking", bookingId: event.params.bookingId, senderId: booking.clientId || "" },
    { excludeUserIds: [booking.clientId] }
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

/**
 * Añade una incidencia leve al cuidador (por ejemplo, por no fichar salida).
 * 5 incidencias leves equivalen a 1 incidencia normal.
 * Las incidencias leves también restan puntuación en las búsquedas.
 */
async function addMinorIncidentToCaregiver(caregiverId, reason) {
  if (!caregiverId) return;
  const db = admin.firestore();
  const cgRef = db.collection("caregivers").doc(caregiverId);
  const userRef = db.collection("users").doc(caregiverId);
  const [cgDoc, userDoc] = await Promise.all([cgRef.get(), userRef.get()]);
  if (!cgDoc.exists && !userDoc.exists) return;

  const baseData = (cgDoc.exists ? cgDoc.data() : userDoc.data()) || {};
  const currentMinor = Number(baseData.minorIncidentsCount) || 0;
  const newMinor = currentMinor + 1;
  const convertedMajor = Math.floor(newMinor / 5);
  const remainingMinor = newMinor % 5;

  const writes = [];
  const updateData = {
    minorIncidentsCount: remainingMinor,
    lastMinorIncidentAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMinorIncidentReason: reason || "Falta de check-out obligatorio",
  };
  if (cgDoc.exists) writes.push(cgRef.set(updateData, { merge: true }));
  if (userDoc.exists) writes.push(userRef.set(updateData, { merge: true }));
  await Promise.all(writes);

  if (convertedMajor > 0) {
    for (let i = 0; i < convertedMajor; i++) {
      await addIncidentToCaregiver(caregiverId);
    }
    console.log(`[Incidencia Leve] Cuidador ${caregiverId} acumuló 5 leves -> convertidas a ${convertedMajor} incidencia normal.`);
  }
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
      { type: "booking", bookingId: event.params.bookingId, senderId: after.clientId || "" },
      { excludeUserIds: [after.clientId] }
    );
  }

  if (before.liveStatus !== "on_the_way" && after.liveStatus === "on_the_way") {
    await sendPushNotification(
      after.clientId,
      "Cuidador en camino",
      `${after.caregiverName || "Tu cuidador/a"} va de camino al servicio del ${formatDateEs(after.day)}.`,
      { type: "tracking", bookingId: event.params.bookingId, senderId: after.caregiverId || "" },
      { excludeUserIds: [after.caregiverId] }
    );
  }

  if (!before.checkInTime && after.checkInTime) {
    await sendPushNotification(
      after.clientId,
      "Servicio iniciado",
      `${after.caregiverName || "Tu cuidador/a"} ha registrado su llegada en el domicilio.`,
      { type: "tracking", bookingId: event.params.bookingId, senderId: after.caregiverId || "" },
      { excludeUserIds: [after.caregiverId] }
    );
  }

  // Notificaciones de pagos y resolución de disputas
  if (before.escrowStatus !== after.escrowStatus) {
    if ((after.escrowStatus === "released_auto" || after.escrowStatus === "released_manual") && after.checkInTime) {
      await sendPushNotification(
        after.caregiverId,
        "¡Pago Recibido!",
        `Has recibido un pago de ${after.caregiverPayout?.toFixed(2)}€ por el servicio del ${formatDateEs(after.day)}.`,
        { type: "payment", bookingId: event.params.bookingId, senderId: after.clientId || "" },
        { excludeUserIds: [after.clientId] }
      );
    } 
    else if (after.escrowStatus === "released_partial" && after.checkInTime) {
      await sendPushNotification(
        after.caregiverId,
        "Pago Recibido (Ajustado)",
        `Has recibido un pago de ${after.caregiverPayout?.toFixed(2)}€. Se ha deducido el tiempo de retraso.`,
        { type: "payment", bookingId: event.params.bookingId, senderId: after.clientId || "" },
        { excludeUserIds: [after.clientId] }
      );
      const refundAmount = after.cost - (after.caregiverPayout + after.caregiverCommissionAmount);
      if (refundAmount > 0) {
        await sendPushNotification(
          after.clientId,
          "Reembolso por Retraso",
          `Hemos procesado un reembolso de ${refundAmount.toFixed(2)}€ a tu método de pago por el retraso del cuidador.`,
          { type: "payment", bookingId: event.params.bookingId, senderId: after.caregiverId || "" },
          { excludeUserIds: [after.caregiverId] }
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
        { type: "payment", bookingId: event.params.bookingId, senderId: after.caregiverId || "" },
        { excludeUserIds: [after.caregiverId] }
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
        { type: "booking", bookingId: event.params.bookingId, senderId: after.clientId || "" },
        { excludeUserIds: [after.clientId] }
      );
    } else if (after.status === "confirmed") {
      if (after.paymentStatus === "paid" || after.escrowStatus === "held") {
        await syncCaregiverClientAccess(after.clientId, after.caregiverId);
      }
      if (before.status === "pendingPayment") {
        // Confirmación iniciada al pagar el cliente (p. ej. al adjudicar una oferta): notificar al cuidador, nunca al propio cliente
        if (!(after.offerId || after.isJobOffer)) {
          await sendPushNotification(
            after.caregiverId,
            "¡Reserva Confirmada!",
            `La familia ha confirmado y asegurado tu servicio para el ${formatDateEs(after.day)} a las ${after.slot}.`,
            { type: "booking", bookingId: event.params.bookingId, senderId: after.clientId || "" },
            { excludeUserIds: [after.clientId] }
          );
        }
      } else {
        // El cuidador aceptó una solicitud pendiente -> notificar al cliente
        await sendPushNotification(
          after.clientId,
          "¡Reserva Confirmada!",
          `${after.caregiverName || "El cuidador"} ha aceptado tu reserva para el ${formatDateEs(after.day)}.`,
          { type: "booking", bookingId: event.params.bookingId, senderId: after.caregiverId || "" },
          { excludeUserIds: [after.caregiverId] }
        );
      }
    } else if (after.status === "cancelled" || after.status === "cancelledLate") {
      const reason = String(after.cancellationReason || "").toLowerCase();
      if (reason.includes("no-show") || reason.includes("no show")) {
        await Promise.all([
          sendPushNotification(
            after.clientId,
            "Reserva cancelada por ausencia",
            `El cuidador no llegó antes de finalizar el horario del ${formatDateEs(after.day)}. La reserva se ha cancelado y recibirás el reembolso íntegro.`,
            { type: "booking", bookingId: event.params.bookingId, senderId: after.caregiverId || "" },
            { excludeUserIds: [after.caregiverId] }
          ),
          sendPushNotification(
            after.caregiverId,
            "Reserva cancelada (No-Show)",
            `No se registró tu entrada antes de finalizar el servicio del ${formatDateEs(after.day)}. La reserva ha sido cancelada y se ha registrado una incidencia.`,
            { type: "booking", bookingId: event.params.bookingId, senderId: after.clientId || "" },
            { excludeUserIds: [after.clientId] }
          ),
        ]);
      } else if (reason.includes("cuidador") || reason.includes("rechazada")) {
        await sendPushNotification(
          after.clientId,
          "Reserva Cancelada",
          `El cuidador ha cancelado o rechazado la reserva del ${formatDateEs(after.day)}.`,
          { type: "booking", bookingId: event.params.bookingId, senderId: after.caregiverId || "" },
          { excludeUserIds: [after.caregiverId] }
        );
      } else if (reason.includes("expirada")) {
        await sendPushNotification(
          after.clientId,
          "Reserva Expirada",
          `La solicitud del ${formatDateEs(after.day)} ha expirado sin confirmación y se ha tramitado el reembolso.`,
          { type: "booking", bookingId: event.params.bookingId }
        );
      } else {
        await sendPushNotification(
          after.caregiverId,
          "Reserva Cancelada",
          `La familia ha cancelado la reserva del ${formatDateEs(after.day)}.`,
          { type: "booking", bookingId: event.params.bookingId, senderId: after.clientId || "" },
          { excludeUserIds: [after.clientId] }
        );
      }
    } else if (after.status === "completed") {
      if (after.escrowStatus !== "released_manual") {
        await sendPushNotification(
          after.clientId,
          "Servicio completado",
          `El servicio del ${formatDateEs(after.day)} ha finalizado. Ya puedes valorar a ${after.caregiverName || "tu cuidador/a"}.`,
          { type: "booking", bookingId: event.params.bookingId, senderId: after.caregiverId || "" },
          { excludeUserIds: [after.caregiverId] }
        );
      }
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
  const amountCents = Math.max(0, Math.round(Number(paymentIntent.amount_received || paymentIntent.amount || 0)));
  if (amountCents <= 0) return;
  const amountEur = amountCents / 100;

  const db = admin.firestore();
  const bookingRef = db.collection("bookings").doc(bookingId);
  const initialSnap = await bookingRef.get();
  if (!initialSnap.exists) return;
  const initialBooking = initialSnap.data() || {};
  const caregiverId = initialBooking.caregiverId;
  if (!caregiverId) return;

  const alreadyProcessedInitial = Array.isArray(initialBooking.processedTipPaymentIntents) &&
    initialBooking.processedTipPaymentIntents.includes(paymentIntent.id);
  if (alreadyProcessedInitial) return;

  const cgDoc = await db.collection("caregivers").doc(caregiverId).get();
  const dest = cgDoc.exists ? String(cgDoc.data()?.stripeAccountId || "").trim() : "";
  if (!dest) {
    throw new Error(`Caregiver ${caregiverId} has no stripeAccountId for tip transfer.`);
  }

  // Execute idempotent transfer FIRST before marking processedTipPaymentIntents in Firestore
  await createLinkedStripeTransfer(stripe, {
    amountInCents: amountCents,
    destination: dest,
    paymentIntentId: paymentIntent.id,
    transferGroup: paymentIntent.transfer_group || undefined,
    idempotencyKey: `tip_transfer_${paymentIntent.id}`,
  });

  const newlyRecorded = await db.runTransaction(async (tx) => {
    const snap = await tx.get(bookingRef);
    if (!snap.exists) return false;
    const b = snap.data() || {};
    const processed = Array.isArray(b.processedTipPaymentIntents) ? b.processedTipPaymentIntents : [];
    if (processed.includes(paymentIntent.id)) return false;

    tx.update(bookingRef, {
      tipAmount: admin.firestore.FieldValue.increment(amountEur),
      tipAmountCents: admin.firestore.FieldValue.increment(amountCents),
      processedTipPaymentIntents: admin.firestore.FieldValue.arrayUnion(paymentIntent.id),
    });
    return true;
  });

  if (newlyRecorded) {
    await sendPushNotification(
      caregiverId,
      "¡Has recibido una propina!",
      `La familia te ha enviado ${amountEur.toFixed(2)}€ de propina íntegra por tu servicio.`,
      { type: "payment", bookingId }
    );
  }
}

async function findBookingsForPaymentIntent(db, rawIntent) {
  let docs = (await db.collection("bookings").where("paymentIntentId", "==", rawIntent.id).get()).docs;
  if (docs.length === 0 && rawIntent.transfer_group) {
    docs = (await db.collection("bookings").where("transferGroup", "==", rawIntent.transfer_group).get()).docs;
  }
  if (docs.length === 0 && typeof rawIntent.metadata?.bookingIds === "string" && rawIntent.metadata.bookingIds.trim()) {
    const metaIds = [...new Set(rawIntent.metadata.bookingIds.split(",").map((s) => s.trim()).filter(Boolean))];
    const fetched = await Promise.all(metaIds.map((id) => db.collection("bookings").doc(id).get()));
    docs = fetched.filter((d) => d.exists);
  }
  return docs;
}

// --- STRIPE WEBHOOK ---
exports.stripeWebhook = functions.region("europe-west1").runWith({ secrets: [stripeSecret, webhookSecret] }).https.onRequest(async (req, res) => {
    const stripe = require("stripe")(stripeSecret.value());
    const sig = req.headers["stripe-signature"];
    let event;
    try {
      event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret.value());
    } catch (err) {
      console.error("Webhook signature verification failed:", err.message);
      return res.status(400).send("Webhook Error: Invalid signature or payload.");
    }

    const db = admin.firestore();
    const eventRef = db.collection("webhook_events").doc(event.id);
    try {
      const claimResult = await db.runTransaction(async (tx) => {
        const snap = await tx.get(eventRef);
        if (snap.exists) {
          const data = snap.data() || {};
          const ageMs = data.claimedAtMs ? (Date.now() - Number(data.claimedAtMs)) : 0;
          if (data.status === "completed") {
            return { duplicate: true };
          }
          if (data.status === "processing" && ageMs < 2 * 60 * 1000) {
            return { duplicate: true };
          }
        }
        tx.set(eventRef, {
          id: event.id,
          type: event.type,
          status: "processing",
          claimedAtMs: Date.now(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { duplicate: false };
      });
      if (claimResult.duplicate) {
        return res.status(200).json({ received: true, duplicate: true });
      }
    } catch (claimErr) {
      console.error("Error claiming webhook event in transaction:", claimErr);
      return res.status(500).send("Webhook lock error");
    }

    try {
      let eventMeta = {};

      if (event.type === "payment_intent.succeeded") {
        const rawIntent = event.data.object;
        if (String(rawIntent.currency || "").toLowerCase() !== "eur") {
          console.warn(`Ignored non-EUR PaymentIntent ${rawIntent.id}: ${rawIntent.currency}`);
          await eventRef.set({
            type: event.type,
            status: "completed",
            ignored: "non_eur",
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          return res.status(200).json({ received: true });
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
          await applyTipSettlement(stripe, expandedIntent);
          await eventRef.set({
            type: event.type,
            status: "completed",
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          return res.status(200).json({ received: true });
        }

        const docs = await findBookingsForPaymentIntent(db, rawIntent);

        let expectedCents = 0;
        let matchedCount = 0;
        const activeEntries = [];
        const orphanEntries = [];

        for (const doc of docs) {
          const booking = doc.data() || {};
          if (booking.paymentIntentId && booking.paymentIntentId !== rawIntent.id) {
            continue;
          }
          if (rawIntent.metadata?.familyId && booking.clientId && rawIntent.metadata.familyId !== booking.clientId) {
            continue;
          }
          const costCents = Math.round((Number(booking.cost) || 0) * 100);
          const rawFeeRate = Number(booking.clientFeeRate);
          const expectedFeeRate = (Number.isFinite(rawFeeRate) && rawFeeRate >= STANDARD_CLIENT_FEE_RATE && rawFeeRate <= 0.15)
            ? rawFeeRate
            : STANDARD_CLIENT_FEE_RATE;
          const clientFeeCents = Math.round(costCents * expectedFeeRate);
          const totalPaidCents = costCents + clientFeeCents;
          const rawCommRate = Number(booking.caregiverCommissionRate);
          const commissionRate = (Number.isFinite(rawCommRate) && rawCommRate >= 0.05 && rawCommRate <= 0.25)
            ? rawCommRate
            : 0.18;
          const commissionCents = Math.round(costCents * commissionRate);
          const payoutCents = costCents - commissionCents;

          expectedCents += totalPaidCents;
          matchedCount++;

          const isCancelledOrRefunded = ["cancelled", "cancelledLate", "expired"].includes(booking.status) ||
            booking.escrowStatus === "refunded";
          if (isCancelledOrRefunded) {
            orphanEntries.push({ doc, booking, totalPaidCents });
          } else {
            activeEntries.push({
              doc,
              booking,
              clientFee: clientFeeCents / 100,
              commissionAmount: commissionCents / 100,
              caregiverPayout: payoutCents / 100,
              totalPaid: totalPaidCents / 100,
            });
          }
        }

        const amountReceived = Number(expandedIntent.amount_received ?? rawIntent.amount_received ?? 0);
        const toleranceCents = Math.max(2, matchedCount * 2);
        if (matchedCount > 0 && amountReceived < (expectedCents - toleranceCents)) {
          console.error(`Fraud/underpayment detected on ${rawIntent.id}: received ${amountReceived} but expected ${expectedCents}.`);
          await db.collection("admin_alerts").add({
            type: "payment_amount_mismatch",
            severity: "critical",
            paymentIntentId: rawIntent.id,
            amountReceivedCents: amountReceived,
            expectedCents,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await eventRef.set({
            type: event.type,
            status: "completed",
            rejected: "insufficient_amount",
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          return res.status(200).send("Payment amount insufficient, bookings not confirmed.");
        }

        for (const orphan of orphanEntries) {
          await db.collection("orphan_payment_alerts").doc(`${rawIntent.id}_${orphan.doc.id}`).set({
            bookingId: orphan.doc.id,
            paymentIntentId: rawIntent.id,
            clientId: orphan.booking.clientId || null,
            caregiverId: orphan.booking.caregiverId || null,
            bookingStatus: orphan.booking.status || null,
            escrowStatus: orphan.booking.escrowStatus || null,
            refundAmountCents: orphan.totalPaidCents,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });

          const refundCents = Math.min(amountReceived, orphan.totalPaidCents);
          if (refundCents > 0) {
            await createIdempotentRefund(stripe, {
              paymentIntentId: rawIntent.id,
              amountInCents: refundCents,
              idempotencyKey: `orphan_pi_refund_${rawIntent.id}_${orphan.doc.id}`,
            });
          }
          await orphan.doc.ref.update({
            escrowStatus: "refunded",
            paymentStatus: "refunded",
            paymentIntentId: rawIntent.id,
          });
        }

        const batch = db.batch();
        const offersToAccept = [];
        const accessToGrant = [];

        for (const entry of activeEntries) {
          const { doc, booking } = entry;
          const isOfferBooking = Boolean(booking.offerId || booking.isJobOffer);
          const newStatus = (booking.status === "confirmed" || isOfferBooking)
            ? "confirmed"
            : (booking.status === "pendingPayment" ? "pending" : booking.status);
          const nextEscrow = (!booking.escrowStatus || booking.escrowStatus === "none")
            ? "held"
            : booking.escrowStatus;

          batch.update(doc.ref, {
            status: newStatus,
            paymentStatus: "paid",
            escrowStatus: nextEscrow,
            paymentIntentId: rawIntent.id,
            paymentMethodType: resolvedMethodType,
            clientFee: entry.clientFee,
            caregiverCommissionAmount: entry.commissionAmount,
            caregiverPayout: entry.caregiverPayout,
            totalPaid: entry.totalPaid,
          });

          if (isOfferBooking && booking.offerId) {
            offersToAccept.push({
              offerId: booking.offerId,
              applicationId: booking.applicationId,
              caregiverId: booking.caregiverId,
            });
          }
          if (newStatus === "confirmed" && booking.clientId && booking.caregiverId) {
            accessToGrant.push([booking.clientId, booking.caregiverId]);
          }
        }

        if (activeEntries.length > 0) {
          await batch.commit();
        }
        for (const offerInfo of offersToAccept) {
          await acceptJobOfferOnPayment(db, offerInfo);
        }
        for (const [cId, cgId] of accessToGrant) {
          await db.collection("clients").doc(cId).collection("caregiver_access").doc(cgId).set({
            caregiverId: cgId,
            active: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }

        eventMeta = { updatedCount: activeEntries.length, orphanCount: orphanEntries.length };
      } else if (event.type === "payment_intent.processing") {
        const rawIntent = event.data.object;
        if (String(rawIntent.currency || "").toLowerCase() === "eur") {
          const docs = await findBookingsForPaymentIntent(db, rawIntent);
          const batch = db.batch();
          const offersToAccept = [];
          let updatedCount = 0;
          for (const doc of docs) {
            const b = doc.data() || {};
            if (b.paymentIntentId && b.paymentIntentId !== rawIntent.id) {
              continue;
            }
            if (["cancelled", "cancelledLate", "expired"].includes(b.status) || b.escrowStatus === "refunded") {
              continue;
            }
            const isOfferBooking = Boolean(b.offerId || b.isJobOffer);
            batch.update(doc.ref, {
              status: b.status === "pendingPayment" ? (isOfferBooking ? "confirmed" : "pending") : b.status,
              escrowStatus: (!b.escrowStatus || b.escrowStatus === "none") ? "held" : b.escrowStatus,
              paymentStatus: "processing",
              paymentIntentId: rawIntent.id,
              paymentMethodType: extractStripePaymentMethodType(rawIntent),
            });
            updatedCount++;
            if (isOfferBooking && b.offerId) {
              offersToAccept.push({
                offerId: b.offerId,
                applicationId: b.applicationId,
                caregiverId: b.caregiverId,
              });
            }
          }
          if (updatedCount > 0) await batch.commit();
          for (const offerInfo of offersToAccept) {
            await acceptJobOfferOnPayment(db, offerInfo);
          }
        }
      } else if (event.type === "payment_intent.payment_failed") {
        const rawIntent = event.data.object;
        const docs = await findBookingsForPaymentIntent(db, rawIntent);

        const batch = db.batch();
        const postActions = [];
        for (const doc of docs) {
          const b = doc.data() || {};
          if (b.paymentIntentId && b.paymentIntentId !== rawIntent.id) continue;
          const prevStatus = b.status;
          const nextStatus = (prevStatus === "pendingPayment" || prevStatus === "pending")
            ? "cancelled"
            : prevStatus;
          batch.update(doc.ref, {
            status: nextStatus,
            paymentStatus: "failed",
            escrowStatus: "payment_failed_frozen",
            paymentFailedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          postActions.push(async () => {
            if (prevStatus === "pendingPayment" || prevStatus === "pending") {
              await reopenBookingSlots(b.caregiverId, b.day, b.slot);
            }
            await syncCaregiverClientAccess(b.clientId, b.caregiverId);
            await db.collection("admin_alerts").add({
              type: "payment_intent_failed",
              severity: (prevStatus === "confirmed" || prevStatus === "completed") ? "critical" : "warning",
              bookingId: doc.id,
              paymentIntentId: rawIntent.id,
              clientId: b.clientId || null,
              caregiverId: b.caregiverId || null,
              previousStatus: prevStatus || null,
              previousEscrowStatus: b.escrowStatus || null,
              failureMessage: rawIntent.last_payment_error?.message || "Payment failed",
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            if (b.clientId) {
              await sendPushNotification(
                b.clientId,
                "Fallo en el pago de la reserva",
                `El banco ha rechazado el cargo de la reserva del ${formatDateEs(b.day)}. Revisa tu método de pago.`,
                { type: "payment", bookingId: doc.id }
              );
            }
            if (b.caregiverId && (prevStatus === "confirmed" || prevStatus === "completed")) {
              await sendPushNotification(
                b.caregiverId,
                "Incidencia bancaria en reserva",
                `El pago bancario de la reserva del ${formatDateEs(b.day)} ha fallado. La custodia queda congelada en revisión.`,
                { type: "booking", bookingId: doc.id }
              );
            }
          });
        }
        if (docs.length > 0) {
          await batch.commit();
          for (const fn of postActions) {
            await fn();
          }
        }
      } else if (event.type === "checkout.session.completed") {
        const session = event.data.object;
        const piId = typeof session.payment_intent === "string"
          ? session.payment_intent
          : session.payment_intent?.id;
        const rawIds = session.metadata?.bookingIds;
        const sessionCurrency = String(session.currency || "eur").toLowerCase();
        if (sessionCurrency === "eur" && piId) {
          const paymentIntent = await stripe.paymentIntents.retrieve(piId, { expand: ["latest_charge"] });
          const isPaidNow = session.payment_status === "paid" || paymentIntent?.status === "succeeded";
          const amountReceived = Number(paymentIntent?.amount_received ?? session.amount_total ?? 0);

          let fetchedSnaps = (await db.collection("bookings").where("checkoutSessionId", "==", session.id).get()).docs;
          if (fetchedSnaps.length === 0 && paymentIntent?.transfer_group) {
            fetchedSnaps = (await db.collection("bookings").where("transferGroup", "==", paymentIntent.transfer_group).get()).docs;
          }
          if (fetchedSnaps.length === 0 && typeof rawIds === "string" && rawIds.trim()) {
            const ids = [...new Set(rawIds.split(",").map((s) => s.trim()).filter(Boolean))];
            fetchedSnaps = await Promise.all(ids.map((id) => db.collection("bookings").doc(id).get()));
          }
          let expectedCents = 0;
          const validEntries = [];
          const orphanEntries = [];

          for (const snap of fetchedSnaps) {
            if (!snap.exists) continue;
            const b = snap.data() || {};
            if (b.paymentIntentId && b.paymentIntentId !== piId) continue;
            if (session.metadata?.familyId && b.clientId && session.metadata.familyId !== b.clientId) continue;
            const costCents = Math.round((Number(b.cost) || 0) * 100);
            const feeRate = Number(b.clientFeeRate) || STANDARD_CLIENT_FEE_RATE;
            const totalPaidCents = Number(b.totalPaid) > 0
              ? Math.round(Number(b.totalPaid) * 100)
              : (costCents + Math.round(costCents * feeRate));
            expectedCents += totalPaidCents;

            if (["cancelled", "cancelledLate", "expired"].includes(b.status) || b.escrowStatus === "refunded") {
              orphanEntries.push({ snap, b, totalPaidCents });
            } else {
              validEntries.push({ snap, b });
            }
          }

          const totalMatched = validEntries.length + orphanEntries.length;
          const toleranceCents = Math.max(2, totalMatched * 2);
          if (isPaidNow && totalMatched > 0 && amountReceived < (expectedCents - toleranceCents)) {
            console.error(`Checkout session underpayment on ${session.id}: received ${amountReceived}, expected ${expectedCents}`);
            await db.collection("admin_alerts").add({
              type: "checkout_session_amount_mismatch",
              severity: "critical",
              sessionId: session.id,
              paymentIntentId: piId,
              amountReceivedCents: amountReceived,
              expectedCents,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            await eventRef.set({
              type: event.type,
              status: "completed",
              rejected: "insufficient_amount",
              processedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            return res.status(200).send("Checkout session amount insufficient.");
          }

          for (const orphan of orphanEntries) {
            await db.collection("orphan_payment_alerts").doc(`${piId}_${orphan.snap.id}`).set({
              bookingId: orphan.snap.id,
              paymentIntentId: piId,
              sessionId: session.id,
              clientId: orphan.b.clientId || null,
              caregiverId: orphan.b.caregiverId || null,
              bookingStatus: orphan.b.status || null,
              escrowStatus: orphan.b.escrowStatus || null,
              refundAmountCents: orphan.totalPaidCents,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            if (isPaidNow && orphan.totalPaidCents > 0) {
              await createIdempotentRefund(stripe, {
                paymentIntentId: piId,
                amountInCents: Math.min(amountReceived, orphan.totalPaidCents),
                idempotencyKey: `orphan_cs_refund_${piId}_${orphan.snap.id}`,
              });
            }
            await orphan.snap.ref.update({
              escrowStatus: "refunded",
              paymentStatus: "refunded",
              paymentIntentId: piId,
              checkoutSessionId: session.id,
            });
          }

          const batch = db.batch();
          const offersToAccept = [];
          const accessToGrant = [];

          for (const { snap, b } of validEntries) {
            const isOfferBooking = Boolean(b.offerId || b.isJobOffer);
            const nextStatus = b.status === "pendingPayment" ? (isOfferBooking ? "confirmed" : "pending") : b.status;
            batch.set(
              snap.ref,
              {
                paymentIntentId: piId,
                checkoutSessionId: session.id,
                paymentStatus: isPaidNow ? "paid" : "processing",
                status: nextStatus,
                escrowStatus: (!b.escrowStatus || b.escrowStatus === "none") ? "held" : b.escrowStatus,
              },
              { merge: true }
            );
            if (isOfferBooking && b.offerId) {
              offersToAccept.push({
                offerId: b.offerId,
                applicationId: b.applicationId,
                caregiverId: b.caregiverId,
              });
            }
            if (nextStatus === "confirmed" && isPaidNow && b.clientId && b.caregiverId) {
              accessToGrant.push([b.clientId, b.caregiverId]);
            }
          }

          if (validEntries.length > 0) await batch.commit();
          for (const offerInfo of offersToAccept) {
            await acceptJobOfferOnPayment(db, offerInfo);
          }
          for (const [cId, cgId] of accessToGrant) {
            await db.collection("clients").doc(cId).collection("caregiver_access").doc(cgId).set({
              caregiverId: cgId,
              active: true,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
          eventMeta = { updatedCount: validEntries.length, orphanCount: orphanEntries.length };
        }
      } else if (event.type === "charge.dispute.created") {
        const dispute = event.data.object;
        const piId = typeof dispute.payment_intent === "string"
          ? dispute.payment_intent
          : dispute.payment_intent?.id;
        const affectedBookingIds = [];
        if (piId) {
          const snap = await db.collection("bookings").where("paymentIntentId", "==", piId).get();
          const batch = db.batch();
          for (const doc of snap.docs) {
            affectedBookingIds.push(doc.id);
            batch.update(doc.ref, {
              escrowStatus: "stripe_disputed",
              stripeDisputeId: dispute.id,
              stripeDisputeStatus: dispute.status || "needs_response",
              stripeDisputeAmountCents: Number(dispute.amount) || 0,
              stripeDisputeCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          if (!snap.empty) await batch.commit();
        }
        await db.collection("admin_alerts").doc(`dispute_${dispute.id}`).set({
          type: "charge.dispute.created",
          severity: "urgent",
          stripeDisputeId: dispute.id,
          paymentIntentId: piId || null,
          chargeId: typeof dispute.charge === "string" ? dispute.charge : (dispute.charge?.id || null),
          amountCents: Number(dispute.amount) || 0,
          currency: dispute.currency || "eur",
          reason: dispute.reason || "unknown",
          bookingIds: affectedBookingIds,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      } else if (event.type === "charge.refunded") {
        const charge = event.data.object;
        const piId = typeof charge.payment_intent === "string"
          ? charge.payment_intent
          : charge.payment_intent?.id;
        if (piId) {
          const snap = await db.collection("bookings").where("paymentIntentId", "==", piId).get();
          if (!snap.empty) {
            const amountRefundedCents = Number(charge.amount_refunded) || 0;
            const chargeAmountCents = Number(charge.amount) || 0;
            const isFullyRefunded = charge.refunded === true || (chargeAmountCents > 0 && amountRefundedCents >= chargeAmountCents);
            const batch = db.batch();
            for (const doc of snap.docs) {
              const b = doc.data() || {};
              const updateData = {
                refundedAmountCents: amountRefundedCents,
                lastRefundSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
              };
              if (isFullyRefunded && !["released", "released_manual", "released_auto", "resolved_partial"].includes(b.escrowStatus)) {
                updateData.escrowStatus = "refunded";
                updateData.paymentStatus = "refunded";
              }
              batch.update(doc.ref, updateData);
            }
            await batch.commit();
          }
        }
      } else if (event.type === "account.updated") {
        const acct = event.data.object;
        if (acct && acct.id) {
          const transfersCapabilityStatus = acct.capabilities?.transfers || "inactive";
          const isKycVerified = Boolean(
            acct.details_submitted &&
            acct.charges_enabled &&
            acct.payouts_enabled &&
            transfersCapabilityStatus === "active"
          );
          const cgSnap = await db.collection("caregivers").where("stripeAccountId", "==", acct.id).get();
          if (!cgSnap.empty) {
            const batch = db.batch();
            for (const doc of cgSnap.docs) {
              batch.update(doc.ref, {
                chargesEnabled: Boolean(acct.charges_enabled),
                payoutsEnabled: Boolean(acct.payouts_enabled),
                detailsSubmitted: Boolean(acct.details_submitted),
                transfersCapabilityStatus,
                isKycVerified,
                stripeAccountUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
            await batch.commit();
          }
        }
      }

      await eventRef.set({
        type: event.type,
        status: "completed",
        ...eventMeta,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return res.status(200).json({ received: true });
    } catch (webhookErr) {
      console.error(`Fatal error processing webhook ${event.id} (${event.type}):`, webhookErr);
      await eventRef.set({
        status: "failed",
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true }).catch(() => {});
      return res.status(500).send("Internal Webhook Processing Error");
    }
});

// 4. Nueva Oferta de Trabajo (Se notifica solo a cuidadores cercanos, excluyendo al creador y su dispositivo)
exports.pushOnJobOfferCreated = onDocumentCreated({
  document: "job_offers/{offerId}",
  region: "europe-west1"
}, async (event) => {
  const offer = event.data.data() || {};
  const db = admin.firestore();
  const now = new Date();

  const offerLat = Number(offer.clientLatitude);
  const offerLng = Number(offer.clientLongitude);
  const hasOfferCoords =
    Number.isFinite(offerLat) &&
    Number.isFinite(offerLng) &&
    (offerLat !== 0 || offerLng !== 0);

  const clientUids = await resolveTargetUserIds(db, offer.clientId);
  const clientUserSnaps = await Promise.all(
    [...clientUids].map((uid) => db.collection("users").doc(uid).get())
  );
  const excludedTokens = new Set(
    clientUserSnaps
      .filter((doc) => doc.exists && typeof doc.data()?.fcmToken === "string" && doc.data().fcmToken.trim())
      .map((doc) => doc.data().fcmToken.trim())
  );

  const caregiversSnap = await db.collection("caregivers").get();
  const nearbyCaregiverIds = [];

  caregiversSnap.forEach((doc) => {
    const cg = doc.data() || {};
    if (clientUids.has(doc.id)) return;
    const isApproved = cg.verificationStatus === "approved" || cg.verified === true;
    if (!isApproved) return;
    if (cg.accountStatus === "suspended" || cg.status === "suspended") return;
    if (cg.blockedUntil && typeof cg.blockedUntil.toDate === "function" && cg.blockedUntil.toDate() > now) {
      return;
    }

    if (hasOfferCoords) {
      const cgLat = Number(cg.latitude);
      const cgLng = Number(cg.longitude);
      if (!Number.isFinite(cgLat) || !Number.isFinite(cgLng) || (cgLat === 0 && cgLng === 0)) {
        return;
      }
      const maxRadiusKm = Number.isFinite(Number(cg.maxDistanceRadius)) && Number(cg.maxDistanceRadius) > 0
        ? Number(cg.maxDistanceRadius)
        : 50;
      const distKm = haversineDistanceKm(offerLat, offerLng, cgLat, cgLng);
      if (distKm > maxRadiusKm) return;
    }

    nearbyCaregiverIds.push(doc.id);
  });

  if (nearbyCaregiverIds.length === 0) {
    console.log(`Oferta ${event.params.offerId}: sin cuidadores cercanos verificados para notificar.`);
    return null;
  }

  const userSnaps = await Promise.all(
    nearbyCaregiverIds.map((uid) => db.collection("users").doc(uid).get())
  );

  const tokens = [];
  const seenTokens = new Set();
  userSnaps.forEach((doc) => {
    if (!doc.exists) return;
    const data = doc.data() || {};
    if (data.role && data.role !== "caregiver") return;
    const token = typeof data.fcmToken === "string" ? data.fcmToken.trim() : "";
    if (!token || excludedTokens.has(token) || seenTokens.has(token)) return;
    seenTokens.add(token);
    tokens.push(token);
  });

  if (tokens.length > 0) {
    const title = offer.isUrgent ? "⚡ ¡Nueva Oferta Urgente!" : "Nueva Oferta de Trabajo";
    const body = `Un cliente cerca busca cuidador: ${offer.title || "Cuidado a domicilio"}. ¡Aplica ahora!`;

    for (let i = 0; i < tokens.length; i += 500) {
      const chunk = tokens.slice(i, i + 500);
      await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: { title, body },
        data: {
          type: "job_offer",
          offerId: event.params.offerId,
          senderId: String(offer.clientId || ""),
        },
      });
    }
    console.log(`Push enviada a ${tokens.length} cuidadores cercanos por la oferta ${event.params.offerId}`);
  }
  return null;
});

// 5. Nueva Solicitud/Contraoferta (Se notifica al cliente)
exports.pushOnApplicationCreated = onDocumentCreated({
  document: "job_offers/{offerId}/applications/{appId}",
  region: "europe-west1"
}, async (event) => {
  const application = event.data.data() || {};
  
  // Obtenemos la oferta para saber quién es el cliente
  const offerRef = admin.firestore().collection("job_offers").doc(event.params.offerId);
  const offerDoc = await offerRef.get();
  if (!offerDoc.exists) return null;
  const offer = offerDoc.data() || {};

  await offerRef.update({
    applicationsCount: admin.firestore.FieldValue.increment(1),
  }).catch(() => {});

  if (!offer.clientId || offer.clientId === application.caregiverId) {
    return null;
  }

  await sendPushNotification(
    offer.clientId,
    "¡Nueva Solicitud Recibida!",
    `${application.caregiverName || "Un cuidador"} ha aplicado a tu oferta "${offer.title || ""}".`,
    {
      type: "job_application",
      offerId: event.params.offerId,
      applicationId: event.params.appId,
      senderId: String(application.caregiverId || ""),
    },
    { excludeUserIds: [application.caregiverId] }
  );
  return null;
});

// 6. Solicitud Aceptada (Se notifica al cuidador)
exports.pushOnApplicationUpdated = onDocumentUpdated({
  document: "job_offers/{offerId}/applications/{appId}",
  region: "europe-west1"
}, async (event) => {
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};

  if (before.status !== "accepted" && after.status === "accepted") {
    const offerDoc = await admin.firestore().collection("job_offers").doc(event.params.offerId).get();
    if (!offerDoc.exists) return null;
    const offer = offerDoc.data() || {};

    if (!after.caregiverId || after.caregiverId === offer.clientId) {
      return null;
    }

    await sendPushNotification(
      after.caregiverId,
      "¡Enhorabuena! Solicitud Aceptada",
      `El cliente ha aceptado tu perfil para la oferta "${offer.title || ""}".`,
      {
        type: "job_application_accepted",
        offerId: event.params.offerId,
        senderId: String(offer.clientId || ""),
      },
      { excludeUserIds: [offer.clientId] }
    );
  }
  return null;
});


exports.adminBlockCaregiver = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!(await isAdminCaller(context))) throw new functions.https.HttpsError("permission-denied", "Solo administradores verificados.");
  const { caregiverId, days } = data || {};
  if (!caregiverId || typeof caregiverId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "caregiverId requerido.");
  }
  if (!Number.isInteger(days) || days < 0 || days > 3650) {
    throw new functions.https.HttpsError("invalid-argument", "El parámetro days debe ser un número entero entre 0 y 3650.");
  }
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
  const db = admin.firestore();
  const chatRef = db.collection("chats").doc(chatId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    return null;
  }

  const messagesRef = db.collection(`chats/${chatId}/messages`);
  const lastMsgSnapshot = await messagesRef.orderBy("timestamp", "desc").limit(1).get();
  
  if (lastMsgSnapshot.empty) {
    await chatRef.update({
      lastMessage: "",
      lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } else {
    const lastMsgData = lastMsgSnapshot.docs[0].data() || {};
    await chatRef.update({
      lastMessage: lastMsgData.text || "",
      lastMessageTimestamp: lastMsgData.timestamp || admin.firestore.FieldValue.serverTimestamp(),
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
    if (typeof invite.invitedEmail === "string" && invite.invitedEmail.trim()) {
      const callerEmail = (context.auth.token?.email || "").trim().toLowerCase();
      const callerVerified = context.auth.token?.email_verified === true;
      if (!callerVerified || callerEmail !== invite.invitedEmail.trim().toLowerCase()) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Esta invitación está reservada para un correo electrónico específico y verificado."
        );
      }
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
  try {
    await admin.auth().revokeRefreshTokens(memberUid);
  } catch (revokeErr) {
    console.warn(`Could not revoke refresh tokens for ${memberUid}:`, revokeErr.message);
  }
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
      if (k === "checkInPinHash" || k === "bookingPinHash" || k === "pinSalt" || k === "escrowLock") continue;
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
    const unsettledStatuses = ["held", "disputed", "stripe_disputed", "payout_blocked"];
    const [unsettledClientSnap, unsettledCaregiverSnap] = await Promise.all([
      db.collection("bookings")
        .where("clientId", "==", uid)
        .where("escrowStatus", "in", unsettledStatuses)
        .limit(1)
        .get(),
      db.collection("bookings")
        .where("caregiverId", "==", uid)
        .where("escrowStatus", "in", unsettledStatuses)
        .limit(1)
        .get(),
    ]);
    if (!unsettledClientSnap.empty || !unsettledCaregiverSnap.empty) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "No puedes eliminar tu cuenta mientras tengas reservas con fondos en custodia (escrow) o disputas pendientes de liquidar."
      );
    }

    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    const activeFamilyId = userSnap.data()?.activeFamilyId;

    const availabilityCol = db.collection("caregivers").doc(uid).collection("availability");
    const availabilityDaysSnap = await availabilityCol.get();
    for (const dayDoc of availabilityDaysSnap.docs) {
      await deleteCollectionDocs(dayDoc.ref.collection("slots"));
    }

    await Promise.all([
      deleteCollectionDocs(db.collection("caregivers").doc(uid).collection("private")),
      deleteCollectionDocs(availabilityCol),
      deleteCollectionDocs(db.collection("users").doc(uid).collection("notifications")),
      deleteCollectionDocs(db.collection("clients").doc(uid).collection("invites")),
      deleteCollectionDocs(db.collection("clients").doc(uid).collection("caregiver_access")),
    ]);

    try {
      const bucket = admin.storage().bucket();
      const storageFolders = [
        "caregiver_docs",
        "caregiver_avatars",
        "caregiver_voice",
        "client_avatars",
      ];
      const prefixes = [];
      for (const folder of storageFolders) {
        prefixes.push(`${folder}/${uid}_`, `${folder}/${uid}/`);
      }
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
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Error in deleteUserAccountRgpd:", error);
    throw new functions.https.HttpsError("internal", "No se pudo completar la eliminación de la cuenta en este momento.");
  }
});

// =========================================================================
// ALTERNATIVE CHECKOUT (BIZUM / REDIRECT WALLETS) & STATUS VERIFICATION
// =========================================================================

exports.createAlternativeCheckoutSession = functions
  .region("europe-west1")
  .runWith({ secrets: [stripeSecret] })
  .https.onCall(async (data, context) => {
    try {
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
        ? [...new Set(data.bookingIds.map((b) => String(b).trim()).filter(Boolean))]
        : [];
    if (bookingIds.length === 0) {
      throw new functions.https.HttpsError("failed-precondition", "Usa createSecureBooking con reservas registradas en el servidor.");
    }

    const preferredMethod = String(data?.preferredMethod || "bizum").toLowerCase().trim();
    const db = admin.firestore();
    const docs = await Promise.all(bookingIds.map((id) => db.collection("bookings").doc(id).get()));
    let computedTotalCents = 0;
    let transferGroup = `booking_${Date.now()}`;
    let caregiverId = "";
    const oldPiIds = new Set();
    const oldSessionIds = new Set();

    for (const snap of docs) {
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
      }
      const b = snap.data() || {};
      if (b.clientId !== familyId) {
        throw new functions.https.HttpsError("permission-denied", "La reserva no pertenece a esta familia.");
      }
      if (b.paymentStatus === "paid" || b.paymentStatus === "processing") {
        throw new functions.https.HttpsError("failed-precondition", "La reserva ya ha sido pagada o su pago está en procesamiento.");
      }
      if (["cancelled", "cancelledLate", "expired"].includes(b.status)) {
        throw new functions.https.HttpsError("failed-precondition", "La reserva está cancelada o ha expirado.");
      }
      if (preferredMethod === "sepa_debit") {
        const startDt = parseBookingStartDateTime(b.day, b.slot);
        if (!startDt || ((startDt.getTime() - Date.now()) / (3600 * 1000)) < 120) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "El adeudo directo SEPA solo está disponible para reservas con al menos 5 días (120 horas) de antelación."
          );
        }
      }
      const costCents = Math.round((Number(b.cost) || 0) * 100);
      const feeRate = Number(b.clientFeeRate) || STANDARD_CLIENT_FEE_RATE;
      const bookingPaidCents = Number(b.totalPaid) > 0
        ? Math.round(Number(b.totalPaid) * 100)
        : (costCents + Math.round(costCents * feeRate));
      computedTotalCents += bookingPaidCents;
      if (b.transferGroup) transferGroup = b.transferGroup;
      if (b.caregiverId) caregiverId = b.caregiverId;
      if (b.paymentIntentId) oldPiIds.add(b.paymentIntentId);
      if (b.checkoutSessionId) oldSessionIds.add(b.checkoutSessionId);
    }

    const amountInCents = computedTotalCents;
    if (!Number.isFinite(amountInCents) || amountInCents < 50) {
      throw new functions.https.HttpsError("invalid-argument", "El importe mínimo para este pago es 0,50 €.");
    }

    const stripe = require("stripe")(stripeSecret.value());
    for (const oldSessionId of oldSessionIds) {
      await stripe.checkout.sessions.expire(oldSessionId).catch(() => {});
    }
    for (const oldPiId of oldPiIds) {
      try {
        const oldPi = await stripe.paymentIntents.retrieve(oldPiId);
        if (oldPi && (oldPi.status === "succeeded" || oldPi.status === "processing")) {
          throw new functions.https.HttpsError("failed-precondition", "El pago de esta reserva ya se ha completado o está en procesamiento.");
        }
        if (oldPi && ["requires_payment_method", "requires_confirmation", "requires_action", "requires_capture"].includes(oldPi.status)) {
          await stripe.paymentIntents.cancel(oldPiId);
        }
      } catch (piErr) {
        if (piErr instanceof functions.https.HttpsError) throw piErr;
      }
    }

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

    const prevKeyPart = [...oldPiIds, ...oldSessionIds].join("_").slice(0, 60) || "init";
    const csKeyBase = `cs_alt_${bookingIds[0]}_${amountInCents}_${preferredMethod}_${prevKeyPart}`;
    let session;
    let fallbackUsed = false;
    try {
      const methodList = PAYMENT_PREFERENCE_METHOD_TYPES[preferredMethod];
      session = await stripe.checkout.sessions.create(
        {
          ...sessionBase,
          ...(methodList ? { payment_method_types: methodList } : {}),
        },
        { idempotencyKey: `${csKeyBase}_primary`.slice(0, 250) }
      );
    } catch (explicitErr) {
      console.warn(
        `Checkout Session '${preferredMethod}' fallback to Dashboard dynamic methods:`,
        explicitErr.message
      );
      fallbackUsed = true;
      session = await stripe.checkout.sessions.create(
        sessionBase,
        { idempotencyKey: `${csKeyBase}_fallback`.slice(0, 250) }
      );
    }

    const piId = typeof session.payment_intent === "string"
      ? session.payment_intent
      : session.payment_intent?.id || null;
    const batch = db.batch();
    for (const snap of docs) {
      const updateObj = { checkoutSessionId: session.id };
      if (piId) updateObj.paymentIntentId = piId;
      batch.update(snap.ref, updateObj);
    }
    await batch.commit();

    return {
      sessionId: session.id,
      url: session.url,
      transferGroup,
      paymentIntentId: piId,
      requestedMethod: preferredMethod,
      fallbackUsed,
    };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("Error in createAlternativeCheckoutSession:", error);
      throw new functions.https.HttpsError("internal", "No se pudo iniciar la sesión de pago alternativa en este momento.");
    }
  });

exports.verifyStripePaymentStatus = functions
  .region("europe-west1")
  .runWith({ secrets: [stripeSecret] })
  .https.onCall(async (data, context) => {
    try {
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
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("Error in verifyStripePaymentStatus:", error);
      throw new functions.https.HttpsError("internal", "No se pudo verificar el estado del pago en este momento.");
    }
  });

exports.stripeCheckoutRedirect = functions
  .region("europe-west1")
  .https.onRequest((req, res) => {
    const status = String(req.query.status || "success") === "cancelled" ? "cancelled" : "success";
    const rawSessionId = String(req.query.session_id || "").trim();
    const validSessionId = /^(cs_(test|live)_[A-Za-z0-9_]+)$/.test(rawSessionId) ? rawSessionId : "";
    const sessionId = encodeURIComponent(validSessionId);
    const deepLink = validSessionId
      ? `senicare://checkout-return?status=${status}&session_id=${sessionId}`
      : `senicare://checkout-return?status=${status}`;
    const isSuccess = status === "success";
    res
      .set("Content-Type", "text/html; charset=utf-8")
      .set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
      .set("X-Frame-Options", "DENY")
      .set("X-Content-Type-Options", "nosniff")
      .set("Referrer-Policy", "no-referrer")
      .status(200)
      .send(`<!DOCTYPE html>
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
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
      }
      const uid = context.auth.uid;
      const bookingIds = Array.isArray(data?.bookingIds)
        ? [...new Set(data.bookingIds.map((id) => String(id).trim()).filter(Boolean))]
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

    let expectedCents = 0;
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
      if (["cancelled", "cancelledLate", "expired"].includes(b.status) || b.escrowStatus === "refunded") {
        throw new functions.https.HttpsError("failed-precondition", "Esta reserva fue cancelada o ha expirado.");
      }
      const costCents = Math.round((Number(b.cost) || 0) * 100);
      const feeRate = Number(b.clientFeeRate) || STANDARD_CLIENT_FEE_RATE;
      const bookingPaidCents = Number(b.totalPaid) > 0
        ? Math.round(Number(b.totalPaid) * 100)
        : (costCents + Math.round(costCents * feeRate));
      expectedCents += bookingPaidCents;
    }

    const toleranceCents = Math.max(2, docs.length * 2);
    const verifiedAmountCents = isPaid
      ? Number(paymentIntent.amount_received ?? paymentIntent.amount ?? 0)
      : Number(paymentIntent.amount || 0);
    if (verifiedAmountCents < (expectedCents - toleranceCents)) {
      throw new functions.https.HttpsError("permission-denied", "El importe pagado en Stripe es inferior al total de la reserva.");
    }

    const resolvedMethod = extractStripePaymentMethodType(paymentIntent);
    const resolvedPaymentStatus = isPaid ? "paid" : "processing";
    const batch = db.batch();
    const offersToAccept = [];
    const accessToGrant = [];

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
      if (sessionId && !b.checkoutSessionId) {
        updatePayload.checkoutSessionId = sessionId;
      }
      if (transferGroup && !b.transferGroup) {
        updatePayload.transferGroup = transferGroup;
      }
      batch.update(snap.ref, updatePayload);

      if (isOfferBooking && b.offerId) {
        offersToAccept.push({
          offerId: b.offerId,
          applicationId: b.applicationId,
          caregiverId: b.caregiverId,
        });
      }
      if (nextStatus === "confirmed" && isPaid && b.clientId && b.caregiverId) {
        accessToGrant.push([b.clientId, b.caregiverId]);
      }
    }
    await batch.commit();

    for (const offerInfo of offersToAccept) {
      await acceptJobOfferOnPayment(db, offerInfo);
    }
    for (const [cId, cgId] of accessToGrant) {
      await db.collection("clients").doc(cId).collection("caregiver_access").doc(cgId).set({
        caregiverId: cgId,
        active: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    return {
      success: true,
      paymentStatus: resolvedPaymentStatus,
      paymentIntentId: paymentIntent.id,
      paymentMethodType: resolvedMethod,
    };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("Error in confirmClientBookingPayment:", error);
      throw new functions.https.HttpsError("internal", "No se pudo confirmar el pago de la reserva en este momento.");
    }
  });

exports.createTipPaymentIntent = functions
  .region("europe-west1")
  .runWith({ secrets: [stripeSecret] })
  .https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
      }
    const uid = context.auth.uid;
    await checkRateLimit(`tip_pi:${uid}`, 15, 10 * 60 * 1000);
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
    if (!(await isFamilyAdmin(booking.clientId, uid))) {
      throw new functions.https.HttpsError("permission-denied", "Solo un Administrador familiar puede enviar propinas.");
    }

    const caregiverSnap = await db.collection("caregivers").doc(booking.caregiverId).get();
    const stripeAccountId = caregiverSnap.exists ? String(caregiverSnap.data()?.stripeAccountId || "").trim() : "";
    if (!stripeAccountId) {
      throw new functions.https.HttpsError("failed-precondition", "El cuidador no tiene cuenta bancaria (Stripe) configurada.");
    }

    const stripe = require("stripe")(stripeSecret.value());
    const cgStripeAccount = await stripe.accounts.retrieve(stripeAccountId);
    if (!isStripeConnectAccountReady(cgStripeAccount)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "La cuenta de cobros del cuidador no tiene habilitadas las transferencias en Stripe."
      );
    }

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
        paidByUid: uid,
      },
      description: `SeniCare · Propina 100% íntegra para ${booking.caregiverName || "cuidador"}`,
      idempotencyKeyBase: `pi_tip_${bookingId}_${uid}_${amountInCents}_${Math.floor(Date.now() / 60000)}`,
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
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("Error in createTipPaymentIntent:", error);
      throw new functions.https.HttpsError("internal", "No se pudo iniciar el pago de la propina en este momento.");
    }
  });

exports.confirmTipPayment = functions
  .region("europe-west1")
  .runWith({ secrets: [stripeSecret] })
  .https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
      }
    const uid = context.auth.uid;
    await checkRateLimit(`confirm_tip:${uid}`, 15, 10 * 60 * 1000);
    const bookingId = typeof data?.bookingId === "string" ? data.bookingId.trim() : "";
    const paymentIntentId = typeof data?.paymentIntentId === "string" ? data.paymentIntentId.trim() : "";
    if (!bookingId || !paymentIntentId) {
      throw new functions.https.HttpsError("invalid-argument", "bookingId y paymentIntentId son obligatorios.");
    }

    const db = admin.firestore();
    const bookingSnap = await db.collection("bookings").doc(bookingId).get();
    if (!bookingSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Reserva no encontrada.");
    }
    const booking = bookingSnap.data() || {};

    const stripe = require("stripe")(stripeSecret.value());
    const pi = await stripe.paymentIntents.retrieve(paymentIntentId, { expand: ["latest_charge"] });
    if (!pi) {
      throw new functions.https.HttpsError("failed-precondition", "El pago de la propina no se encontró en Stripe.");
    }
    if (pi.metadata?.type !== "tip" || pi.metadata?.bookingId !== bookingId) {
      throw new functions.https.HttpsError("permission-denied", "El PaymentIntent no corresponde a esta propina.");
    }

    const callerIsAdmin = await isAdminCaller(context);
    const isAuthorized = callerIsAdmin ||
      (pi.metadata?.paidByUid && pi.metadata.paidByUid === uid) ||
      (await isFamilyAdmin(booking.clientId, uid));
    if (!isAuthorized) {
      throw new functions.https.HttpsError("permission-denied", "No tienes permiso para confirmar esta propina.");
    }

    if (pi.status === "processing") {
      return {
        success: true,
        status: "processing",
        isProcessing: true,
        amountEur: Math.round(Number(pi.amount || 0)) / 100,
      };
    }
    if (pi.status !== "succeeded") {
      throw new functions.https.HttpsError("failed-precondition", "El pago de la propina no está confirmado en Stripe.");
    }

    await applyTipSettlement(stripe, pi);
    return {
      success: true,
      status: "succeeded",
      isProcessing: false,
      amountEur: Math.round(Number(pi.amount_received || pi.amount || 0)) / 100,
    };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("Error in confirmTipPayment:", error);
      throw new functions.https.HttpsError("internal", "No se pudo confirmar la propina en este momento.");
    }
  });

exports.setupAdmin2FA = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  const verified = context.auth.token?.email_verified === true;
  const { isRegistered, adminDoc, email } = await getAdminDocForContext(context);
  if (!email || !verified) {
    throw new functions.https.HttpsError("permission-denied", "Tu correo debe estar verificado.");
  }
  if (!isRegistered) {
    throw new functions.https.HttpsError("permission-denied", "Solo administradores autorizados.");
  }

  const db = admin.firestore();
  const adminRef = adminDoc ? adminDoc.ref : db.collection("admins").doc(email);
  const privateRef = adminRef.collection("private").doc("totp");
  const [currentAdminSnap, privateSnap] = await Promise.all([
    adminRef.get(),
    privateRef.get(),
  ]);
  if (
    (currentAdminSnap.exists && (currentAdminSnap.data()?.["2faEnabled"] === true || Boolean(currentAdminSnap.data()?.secret))) ||
    privateSnap.exists
  ) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "El doble factor (2FA) ya está activado para este administrador. No puede sobrescribirse desde este endpoint."
    );
  }

  const secret = String(data?.secret || "").trim().toUpperCase();
  const code = String(data?.code || "").trim();
  if (!/^[A-Z2-7]{16,64}$/.test(secret)) {
    throw new functions.https.HttpsError("invalid-argument", "Secreto TOTP inválido.");
  }
  if (!verifyTotpCode(secret, code)) {
    throw new functions.https.HttpsError("invalid-argument", "El código de verificación 2FA es incorrecto.");
  }

  await adminRef.set({
    email,
    "2faEnabled": true,
    secret: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  await privateRef.set({
    secret,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await mergeUserClaims(context.auth.uid, {
    admin: true,
    admin2fa: true,
    adminPending2fa: false,
    admin2faAt: Date.now(),
  });
  return { success: true };
});

exports.verifyAdmin2FA = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  const { isRegistered, adminDoc, email } = await getAdminDocForContext(context);
  if (!email || !isRegistered) {
    throw new functions.https.HttpsError("permission-denied", "Solo administradores verificados.");
  }
  await checkRateLimit(`admin2fa:${context.auth.uid}`, 5, 5 * 60 * 1000);
  const code = String(data?.code || "").trim();
  const db = admin.firestore();
  const adminRef = adminDoc ? adminDoc.ref : db.collection("admins").doc(email);
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

  await mergeUserClaims(context.auth.uid, {
    admin: true,
    admin2fa: true,
    adminPending2fa: false,
    admin2faAt: Date.now(),
  });
  return { success: true };
});

exports.adminAddAdmin = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    if (!(await isAdminCaller(context))) {
      throw new functions.https.HttpsError("permission-denied", "Solo administradores verificados.");
    }
    const rawEmail = typeof data?.email === "string" ? data.email.trim().toLowerCase() : "";
    if (!rawEmail || rawEmail.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(rawEmail)) {
      throw new functions.https.HttpsError("invalid-argument", "Correo electrónico de administrador inválido.");
    }
    const callerEmail = (context.auth.token?.email || "").trim().toLowerCase();
    const db = admin.firestore();
    const adminRef = db.collection("admins").doc(rawEmail);
    const existingSnap = await adminRef.get();
    if (existingSnap.exists) {
      await adminRef.set({
        email: rawEmail,
        updatedBy: callerEmail,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } else {
      await adminRef.set({
        email: rawEmail,
        "2faEnabled": false,
        addedBy: callerEmail,
        addedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return { success: true, email: rawEmail };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Error in adminAddAdmin:", error);
    throw new functions.https.HttpsError("internal", "No se pudo añadir el administrador en este momento.");
  }
});

exports.adminRemoveAdmin = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    if (!(await isAdminCaller(context))) {
      throw new functions.https.HttpsError("permission-denied", "Solo administradores verificados.");
    }
    const rawEmail = typeof data?.email === "string" ? data.email.trim().toLowerCase() : "";
    if (!rawEmail || rawEmail.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(rawEmail)) {
      throw new functions.https.HttpsError("invalid-argument", "Correo electrónico de administrador inválido.");
    }
    const callerEmail = (context.auth.token?.email || "").trim().toLowerCase();
    if (rawEmail === callerEmail) {
      throw new functions.https.HttpsError("failed-precondition", "No puedes eliminar tu propia cuenta de administrador.");
    }

    const db = admin.firestore();
    const adminRef = db.collection("admins").doc(rawEmail);
    await adminRef.collection("private").doc("totp").delete().catch(() => {});
    await adminRef.delete();

    try {
      const targetUser = await admin.auth().getUserByEmail(rawEmail);
      if (targetUser && targetUser.uid) {
        await mergeUserClaims(targetUser.uid, {
          admin: null,
          admin2fa: null,
          adminPending2fa: null,
        });
        await admin.auth().revokeRefreshTokens(targetUser.uid);
      }
    } catch (authErr) {
      if (authErr?.code !== "auth/user-not-found") {
        console.warn(`adminRemoveAdmin auth cleanup warning for ${rawEmail}:`, authErr?.message || authErr);
      }
    }

    return { success: true, email: rawEmail };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Error in adminRemoveAdmin:", error);
    throw new functions.https.HttpsError("internal", "No se pudo revocar el acceso de administrador en este momento.");
  }
});

exports.syncUserClaims = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Debe iniciar sesión.");
  }
  const uid = context.auth.uid;
  const db = admin.firestore();
  const patch = {};

  const { isRegistered, adminDoc } = await getAdminDocForContext(context);
  const tokenHasAdmin2fa = context.auth.token?.admin2fa === true;

  if (isRegistered) {
    if (tokenHasAdmin2fa && adminDoc && adminDoc.exists) {
      patch.admin = true;
      patch.admin2fa = true;
      patch.adminPending2fa = false;
    } else {
      patch.admin = false;
      patch.admin2fa = false;
      patch.adminPending2fa = true;
    }
  } else {
    patch.admin = null;
    patch.admin2fa = null;
    patch.adminPending2fa = null;
    patch.admin2faAt = null;
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const activeFamilyId = userSnap.data()?.activeFamilyId;
  if (activeFamilyId && (await isFamilyMember(activeFamilyId, uid))) {
    patch.familyId = activeFamilyId;
  } else {
    patch.familyId = null;
  }

  await mergeUserClaims(uid, patch);
  return {
    success: true,
    familyId: patch.familyId || null,
    isAdmin: patch.admin === true,
    admin2fa: patch.admin2fa === true,
    adminPending2fa: patch.adminPending2fa === true,
  };
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
