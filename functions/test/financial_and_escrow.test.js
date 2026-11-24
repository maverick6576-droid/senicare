"use strict";

process.env.SENICARE_FUNCTIONS_TEST = "true";

const test = require("node:test");
const assert = require("node:assert/strict");
const Module = require("node:module");

// ---------------------------------------------------------------------------
// In-Memory Firestore, Firebase Admin, Firebase Functions & Stripe Test Fakes
// ---------------------------------------------------------------------------

const DELETE_SENTINEL = Symbol("FieldValue.delete");

class IncrementOp {
  constructor(delta) {
    this.delta = Number(delta) || 0;
  }
}

class ArrayUnionOp {
  constructor(items) {
    this.items = items;
  }
}

class FakeTimestamp {
  constructor(ms) {
    this._ms = ms;
  }
  toDate() {
    return new Date(this._ms);
  }
  toMillis() {
    return this._ms;
  }
  static now() {
    return new FakeTimestamp(Date.now());
  }
  static fromDate(d) {
    return new FakeTimestamp(d.getTime());
  }
  static fromMillis(ms) {
    return new FakeTimestamp(ms);
  }
}

function cloneValue(val) {
  if (val === null || val === undefined) return val;
  if (val instanceof FakeTimestamp) return new FakeTimestamp(val.toMillis());
  if (val instanceof Date) return FakeTimestamp.fromDate(val);
  if (Array.isArray(val)) return val.map(cloneValue);
  if (typeof val === "object") {
    const out = {};
    for (const [k, v] of Object.entries(val)) {
      out[k] = cloneValue(v);
    }
    return out;
  }
  return val;
}

function applyPatch(existing, incoming, merge) {
  const base = merge && existing ? cloneValue(existing) : {};
  for (const [key, val] of Object.entries(incoming || {})) {
    if (val === DELETE_SENTINEL) {
      delete base[key];
    } else if (val instanceof IncrementOp) {
      base[key] = (Number(base[key]) || 0) + val.delta;
    } else if (val instanceof ArrayUnionOp) {
      const prev = Array.isArray(base[key]) ? [...base[key]] : [];
      for (const item of val.items) {
        if (!prev.includes(item)) prev.push(item);
      }
      base[key] = prev;
    } else if (val instanceof Date) {
      base[key] = FakeTimestamp.fromDate(val);
    } else {
      base[key] = cloneValue(val);
    }
  }
  return base;
}

class FakeFirestore {
  constructor() {
    this.reset();
  }

  reset() {
    this._docs = new Map();
    this._autoId = 1;
  }

  nextId(prefix = "doc") {
    const id = `${prefix}_${String(this._autoId++).padStart(4, "0")}`;
    return id;
  }

  seed(path, data) {
    this._docs.set(path, applyPatch(null, data, false));
  }

  readRaw(path) {
    const d = this._docs.get(path);
    return d ? cloneValue(d) : undefined;
  }

  collection(name) {
    return new FakeCollectionRef(this, name);
  }

  doc(path) {
    const parts = path.split("/");
    const id = parts[parts.length - 1];
    return new FakeDocRef(this, path, id);
  }

  batch() {
    const ops = [];
    return {
      set: (ref, data, opts) => ops.push(() => ref.set(data, opts)),
      update: (ref, data) => ops.push(() => ref.update(data)),
      delete: (ref) => ops.push(() => ref.delete()),
      commit: async () => {
        for (const op of ops) {
          await op();
        }
      },
    };
  }

  async runTransaction(fn) {
    const pendingWrites = [];
    const tx = {
      get: async (target) => target.get(),
      set: (ref, data, opts) => pendingWrites.push(() => ref.set(data, opts)),
      update: (ref, data) => pendingWrites.push(() => ref.update(data)),
      delete: (ref) => pendingWrites.push(() => ref.delete()),
    };
    const result = await fn(tx);
    for (const write of pendingWrites) {
      await write();
    }
    return result;
  }
}

class FakeDocSnapshot {
  constructor(ref, rawData) {
    this.ref = ref;
    this.id = ref.id;
    this._data = rawData;
    this.exists = rawData !== undefined;
  }
  data() {
    return this._data !== undefined ? cloneValue(this._data) : undefined;
  }
}

class FakeDocRef {
  constructor(db, path, id) {
    this._db = db;
    this.path = path;
    this.id = id;
  }
  collection(subName) {
    return new FakeCollectionRef(this._db, `${this.path}/${subName}`);
  }
  async get() {
    return new FakeDocSnapshot(this, this._db._docs.get(this.path));
  }
  async set(data, opts) {
    const merge = Boolean(opts && opts.merge);
    const current = this._db._docs.get(this.path);
    this._db._docs.set(this.path, applyPatch(current, data, merge));
  }
  async update(data) {
    const current = this._db._docs.get(this.path);
    if (current === undefined) {
      const err = new Error(`Document not found: ${this.path}`);
      err.code = "not-found";
      throw err;
    }
    this._db._docs.set(this.path, applyPatch(current, data, true));
  }
  async delete() {
    this._db._docs.delete(this.path);
  }
}

class FakeQuery {
  constructor(db, collectionPath, filters = [], limitCount = null) {
    this._db = db;
    this._collectionPath = collectionPath;
    this._filters = filters;
    this._limitCount = limitCount;
  }
  where(field, op, value) {
    return new FakeQuery(
      this._db,
      this._collectionPath,
      [...this._filters, { field, op, value }],
      this._limitCount
    );
  }
  limit(n) {
    return new FakeQuery(this._db, this._collectionPath, this._filters, n);
  }
  async get() {
    const prefix = `${this._collectionPath}/`;
    let docs = [];
    for (const [docPath, raw] of this._db._docs.entries()) {
      if (!docPath.startsWith(prefix)) continue;
      const remainder = docPath.slice(prefix.length);
      if (remainder.includes("/")) continue;
      const matches = this._filters.every(({ field, op, value }) => {
        const fieldVal = raw[field];
        if (op === "==") return fieldVal === value;
        if (op === "in") return Array.isArray(value) && value.includes(fieldVal);
        return false;
      });
      if (matches) {
        docs.push(new FakeDocSnapshot(new FakeDocRef(this._db, docPath, remainder), raw));
      }
    }
    if (this._limitCount !== null) {
      docs = docs.slice(0, this._limitCount);
    }
    return {
      docs,
      empty: docs.length === 0,
      size: docs.length,
    };
  }
}

class FakeCollectionRef extends FakeQuery {
  constructor(db, collectionPath) {
    super(db, collectionPath);
  }
  doc(id) {
    const resolvedId = id || this._db.nextId(this._collectionPath.split("/").pop());
    return new FakeDocRef(this._db, `${this._collectionPath}/${resolvedId}`, resolvedId);
  }
  async add(data) {
    const ref = this.doc();
    await ref.set(data);
    return ref;
  }
}

class HttpsError extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

const fakeDb = new FakeFirestore();

const stripeState = {
  reset() {
    this.accounts = new Map();
    this.paymentIntents = new Map();
    this.createdPaymentIntents = [];
    this.createdRefunds = [];
    this.createdTransfers = [];
    this.cancelledPaymentIntents = [];
    this.webhookSignatureValid = true;
    this.nextWebhookEvent = null;
    this._seq = 1;
  },
};
stripeState.reset();

const fakeStripeClient = {
  accounts: {
    retrieve: async (accountId) => {
      if (stripeState.accounts.has(accountId)) {
        return stripeState.accounts.get(accountId);
      }
      return {
        id: accountId,
        details_submitted: true,
        charges_enabled: true,
        payouts_enabled: true,
        capabilities: { transfers: "active" },
      };
    },
  },
  customers: {
    create: async (params, opts) => ({
      id: `cus_test_${stripeState._seq++}`,
      email: params.email,
      opts,
    }),
  },
  customerSessions: {
    create: async () => ({ client_secret: "cuss_secret_test" }),
  },
  ephemeralKeys: {
    create: async () => ({ secret: "ek_secret_test" }),
  },
  paymentIntents: {
    create: async (params, opts) => {
      const id = `pi_test_${stripeState._seq++}`;
      const pi = {
        id,
        client_secret: `${id}_secret`,
        status: "requires_payment_method",
        currency: params.currency || "eur",
        amount: params.amount,
        amount_received: 0,
        transfer_group: params.transfer_group,
        metadata: params.metadata || {},
        latest_charge: {
          id: `ch_for_${id}`,
          payment_method_details: { type: "card" },
        },
      };
      stripeState.paymentIntents.set(id, pi);
      stripeState.createdPaymentIntents.push({ params, opts, pi });
      return pi;
    },
    retrieve: async (piId) => {
      const existing = stripeState.paymentIntents.get(piId);
      if (!existing) {
        throw new Error(`No such payment_intent: ${piId}`);
      }
      return existing;
    },
    cancel: async (piId) => {
      stripeState.cancelledPaymentIntents.push(piId);
      const existing = stripeState.paymentIntents.get(piId);
      if (existing) existing.status = "canceled";
      return existing || { id: piId, status: "canceled" };
    },
  },
  checkout: {
    sessions: {
      create: async (params, opts) => ({
        id: `cs_test_${stripeState._seq++}`,
        url: "https://checkout.stripe.com/pay/cs_test",
        payment_intent: null,
        params,
        opts,
      }),
      retrieve: async (id) => ({ id, payment_intent: null }),
      expire: async (id) => ({ id, status: "expired" }),
    },
  },
  refunds: {
    create: async (params, opts) => {
      const refund = {
        id: `re_test_${stripeState._seq++}`,
        payment_intent: params.payment_intent,
        amount: params.amount,
        status: "succeeded",
      };
      stripeState.createdRefunds.push({ params, opts, refund });
      return refund;
    },
  },
  transfers: {
    create: async (params, opts) => {
      const transfer = {
        id: `tr_test_${stripeState._seq++}`,
        amount: params.amount,
        destination: params.destination,
        transfer_group: params.transfer_group,
        source_transaction: params.source_transaction || null,
      };
      stripeState.createdTransfers.push({ params, opts, transfer });
      return transfer;
    },
  },
  webhooks: {
    constructEvent: (_rawBody, sig, _secret) => {
      if (!sig || !stripeState.webhookSignatureValid) {
        throw new Error("No signatures found matching the expected signature for payload");
      }
      return stripeState.nextWebhookEvent;
    },
  },
};

function makeFunctionsBuilder() {
  const builder = {
    region: () => builder,
    runWith: () => builder,
    https: {
      onCall: (handler) => handler,
      onRequest: (handler) => handler,
      HttpsError,
    },
    pubsub: {
      schedule: () => ({
        onRun: (handler) => handler,
      }),
    },
  };
  return builder;
}

const fakeFirestoreFn = () => fakeDb;
fakeFirestoreFn.FieldValue = {
  serverTimestamp: () => FakeTimestamp.now(),
  delete: () => DELETE_SENTINEL,
  increment: (n) => new IncrementOp(n),
  arrayUnion: (...items) => new ArrayUnionOp(items),
};
fakeFirestoreFn.Timestamp = FakeTimestamp;

const fakeAdmin = {
  initializeApp: () => {},
  firestore: fakeFirestoreFn,
  messaging: () => ({
    send: async () => "msg_ok",
    sendEachForMulticast: async () => ({ successCount: 1, failureCount: 0, responses: [] }),
  }),
  auth: () => ({
    getUser: async (uid) => ({ uid, customClaims: {} }),
    getUserByEmail: async (email) => ({ uid: `uid_${email}`, email }),
    setCustomUserClaims: async () => {},
    revokeRefreshTokens: async () => {},
  }),
  storage: () => ({
    bucket: () => ({
      file: (p) => ({
        exists: async () => [true],
        getSignedUrl: async () => [`https://storage.googleapis.com/signed/${encodeURIComponent(p)}`],
      }),
      getFiles: async () => [[]],
    }),
  }),
};

const originalLoad = Module._load;
Module._load = function mockedLoad(request, parent, isMain) {
  if (request === "firebase-functions/v1") {
    const fnMod = makeFunctionsBuilder();
    fnMod.https.HttpsError = HttpsError;
    return fnMod;
  }
  if (request === "firebase-functions/params") {
    return {
      defineSecret: (name) => ({
        name,
        value: () => `mock_secret_${name}`,
      }),
    };
  }
  if (request === "firebase-functions/v2/firestore") {
    return {
      onDocumentCreated: (_opts, handler) => handler,
      onDocumentUpdated: (_opts, handler) => handler,
      onDocumentWritten: (_opts, handler) => handler,
      onDocumentDeleted: (_opts, handler) => handler,
    };
  }
  if (request === "firebase-admin") {
    return fakeAdmin;
  }
  if (request === "stripe") {
    return () => fakeStripeClient;
  }
  return originalLoad.call(this, request, parent, isMain);
};

const backend = require("../index.js");
const internals = backend._testInternals;

function createMockRes() {
  return {
    statusCode: 200,
    headers: {},
    body: null,
    setHeader(k, v) {
      this.headers[k] = v;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    send(payload) {
      this.body = payload;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

function formatYmdMadrid(date) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Madrid",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return fmt.format(date);
}

function formatHmMadrid(date) {
  const fmt = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Madrid",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  return fmt.format(date);
}

// ---------------------------------------------------------------------------
// 1. Option 1 Commission & Family Shield Unit Tests
// ---------------------------------------------------------------------------

test("Option 1 — Caregiver loyalty commission tiers (18%/14%/10%) and 8% urgency floor", () => {
  assert.equal(internals.computeServerCommissionRate(0, 0), 0.18);
  assert.equal(internals.computeServerCommissionRate(30, 0), 0.18);
  assert.equal(internals.computeServerCommissionRate(31, 0), 0.14);
  assert.equal(internals.computeServerCommissionRate(100, 0), 0.14);
  assert.equal(internals.computeServerCommissionRate(101, 0), 0.10);

  // Urgency bonus (-10%) respects strict 8% sustainability floor
  assert.ok(Math.abs(internals.computeServerCommissionRate(10, 0.10) - 0.08) < 1e-9);
  assert.ok(Math.abs(internals.computeServerCommissionRate(50, 0.10) - 0.08) < 1e-9);
  assert.ok(Math.abs(internals.computeServerCommissionRate(150, 0.10) - 0.08) < 1e-9);
});

test("Option 1 — Family Protection Shield tiers (5%/3.5%/2%), 4h+ -50% bonus & minimum fee floor", () => {
  assert.equal(internals.computeServerClientFeeRate(0, false), 0.05);
  assert.equal(internals.computeServerClientFeeRate(45, false), 0.035);
  assert.equal(internals.computeServerClientFeeRate(120, false), 0.02);

  // 4h+ Multi-Session Pack halves the Family Shield fee without touching caregiver base salary
  assert.equal(internals.computeServerClientFeeRate(10, true), 0.025);
  assert.equal(internals.computeServerClientFeeRate(45, true), 0.0175);
  assert.equal(internals.computeServerClientFeeRate(120, true), 0.01);

  // Minimum fee floors in integer cents
  assert.equal(internals.computeMinimumClientFeeCents(10, false), 150);
  assert.equal(internals.computeMinimumClientFeeCents(50, false), 125);
  assert.equal(internals.computeMinimumClientFeeCents(120, false), 100);
  assert.equal(internals.computeMinimumClientFeeCents(10, true), 75);
});

// ---------------------------------------------------------------------------
// 2. createSecureBooking Integration Tests
// ---------------------------------------------------------------------------

test("createSecureBooking — computes integer-cent totals, preserves 100% caregiver salary on 4h+ pack, and stores salted PIN/QR secrets", async () => {
  fakeDb.reset();
  stripeState.reset();

  fakeDb.seed("clients/fam_1", {
    ownerUid: "fam_1",
    name: "Familia García",
    latitude: 41.3874,
    longitude: 2.1686,
  });
  fakeDb.seed("caregivers/cg_1", {
    name: "Elena Ruiz",
    verificationStatus: "approved",
    status: "active",
    pricePerHour: 15,
    stripeAccountId: "acct_cg_1",
    isKycVerified: true,
    transfersCapabilityStatus: "active",
  });
  fakeDb.seed("client_caregiver_stats/fam_1_cg_1", {
    accumulatedHours: 10, // Tier 1: 18% caregiver comm, 5% family shield
  });

  // Case A: 4h Multi-Session Pack @ 15€/h = 60.00€ base
  // Caregiver receives 82% of full 60.00€ = 49.20€ (NO 5% salary cut!)
  // Family Shield is halved (-50% of 5% = 2.5% -> 1.50€) -> Total = 61.50€ (6150 cents)
  const resPack = await backend.createSecureBooking(
    {
      caregiverId: "cg_1",
      sessions: [{ day: "2026-12-15", slot: "09:00-13:00" }],
      preferredMethod: "card",
      checklist: ["Medicación desayuno", "Paseo matinal"],
    },
    { auth: { uid: "fam_1", token: { email: "familia@test.com" } } }
  );

  assert.equal(resPack.bookingIds.length, 1);
  assert.equal(resPack.totalEur, 61.5);
  assert.equal(resPack.discountApplied, true);
  assert.equal(stripeState.createdPaymentIntents.length, 1);
  assert.equal(stripeState.createdPaymentIntents[0].params.amount, 6150);
  assert.ok(stripeState.createdPaymentIntents[0].opts.idempotencyKey.startsWith("pi_secure_"));

  const bookingId = resPack.bookingIds[0];
  const savedBooking = fakeDb.readRaw(`bookings/${bookingId}`);
  assert.equal(savedBooking.cost, 60.0);
  assert.equal(savedBooking.clientFee, 1.5);
  assert.equal(savedBooking.clientFeeRate, 0.025);
  assert.equal(savedBooking.caregiverCommissionRate, 0.18);
  assert.equal(savedBooking.caregiverCommissionAmount, 10.8);
  assert.equal(savedBooking.caregiverPayout, 49.2);
  assert.equal(savedBooking.totalPaid, 61.5);
  assert.equal(savedBooking.disputeEscalated, false);
  assert.equal(savedBooking.bookingPinHash, undefined); // Never stored on booking doc!

  const secretDoc = fakeDb.readRaw(`bookings/${bookingId}/secrets/checkin`);
  assert.equal(secretDoc.bookingPin, resPack.bookingPin);
  assert.equal(secretDoc.qrToken.length, 32);

  // Overlapping booking on the same day/slot is rejected atomically
  await assert.rejects(
    () =>
      backend.createSecureBooking(
        {
          caregiverId: "cg_1",
          sessions: [{ day: "2026-12-15", slot: "11:00-13:00" }],
        },
        { auth: { uid: "fam_1", token: { email: "familia@test.com" } } }
      ),
    (err) => err.code === "failed-precondition"
  );
});

test("createSecureBooking — enforces 1.50€ minimum Family Shield fee on short 1-hour shifts", async () => {
  fakeDb.reset();
  stripeState.reset();

  fakeDb.seed("clients/fam_short", { ownerUid: "fam_short" });
  fakeDb.seed("caregivers/cg_short", {
    name: "Carlos Pérez",
    verificationStatus: "approved",
    status: "active",
    pricePerHour: 15,
    stripeAccountId: "acct_cg_short",
  });

  // 1h @ 15€/h: 5% would be 0.75€, minimum floor raises shield fee to 1.50€ -> 16.50€ (1650 cents)
  const res = await backend.createSecureBooking(
    {
      caregiverId: "cg_short",
      sessions: [{ day: "2026-12-18", slot: "10:00-11:00" }],
    },
    { auth: { uid: "fam_short", token: { email: "short@test.com" } } }
  );

  assert.equal(res.totalEur, 16.5);
  assert.equal(stripeState.createdPaymentIntents[0].params.amount, 1650);
});

// ---------------------------------------------------------------------------
// 3. recordBookingCheckOut (Normal & Early Check-Out) Tests
// ---------------------------------------------------------------------------

test("recordBookingCheckOut — normal check-out completes shift without refund and preserves full payout", async () => {
  fakeDb.reset();
  stripeState.reset();

  const now = new Date();
  const start = new Date(now.getTime() - 115 * 60 * 1000); // started 115m ago
  const end = new Date(now.getTime() + 5 * 60 * 1000); // ends in 5m (<= 15m threshold -> normal!)
  const day = formatYmdMadrid(start);
  const slot = `${formatHmMadrid(start)}-${formatHmMadrid(end)}`;

  fakeDb.seed("bookings/bk_normal", {
    id: "bk_normal",
    clientId: "fam_1",
    caregiverId: "cg_1",
    caregiverName: "Elena Ruiz",
    day,
    slot,
    status: "confirmed",
    escrowStatus: "held",
    paymentStatus: "paid",
    paymentIntentId: "pi_normal_1",
    cost: 30,
    clientFee: 1.5,
    totalPaid: 31.5,
    caregiverCommissionRate: 0.18,
    caregiverCommissionAmount: 5.4,
    caregiverPayout: 24.6,
    checkInTime: FakeTimestamp.fromDate(start),
  });

  const out = await backend.recordBookingCheckOut(
    {
      bookingId: "bk_normal",
      careNotes: "Paseo tranquilo y toma de medicación completada sin incidencias.",
    },
    { auth: { uid: "cg_1" } }
  );

  assert.equal(out.success, true);
  assert.equal(out.isEarlyCheckOut, false);
  assert.equal(out.refundAmount, 0);
  assert.equal(out.newPayout, 24.6);
  assert.equal(stripeState.createdRefunds.length, 0);

  const updated = fakeDb.readRaw("bookings/bk_normal");
  assert.equal(updated.status, "completed");
  assert.equal(updated.escrowStatus, "held");
});

test("recordBookingCheckOut — early check-out (>15m early) prorates integer cents, issues idempotent partial refund, and keeps escrow held for worked payout", async () => {
  fakeDb.reset();
  stripeState.reset();

  const now = new Date();
  const start = new Date(now.getTime() - 60 * 60 * 1000); // 60m worked
  const end = new Date(now.getTime() + 60 * 60 * 1000); // 60m early (total 120m shift)
  const day = formatYmdMadrid(start);
  const slot = `${formatHmMadrid(start)}-${formatHmMadrid(end)}`;

  if (day !== formatYmdMadrid(end)) {
    // Skip midnight-crossing edge case only if test runs between 23:00-01:00 Madrid time
    return;
  }

  fakeDb.seed("bookings/bk_early", {
    id: "bk_early",
    clientId: "fam_1",
    caregiverId: "cg_1",
    caregiverName: "Elena Ruiz",
    day,
    slot,
    status: "confirmed",
    escrowStatus: "held",
    paymentStatus: "paid",
    paymentIntentId: "pi_early_1",
    cost: 30, // 3000 cents -> 50% worked = 1500 cents
    clientFee: 1.5,
    totalPaid: 31.5,
    caregiverCommissionRate: 0.18,
    caregiverCommissionAmount: 5.4,
    caregiverPayout: 24.6,
    checkInTime: FakeTimestamp.fromDate(start),
  });

  const out = await backend.recordBookingCheckOut(
    {
      bookingId: "bk_early",
      careNotes: "La familia regresó antes a casa y solicitó finalizar el turno.",
    },
    { auth: { uid: "cg_1" } }
  );

  assert.equal(out.success, true);
  assert.equal(out.isEarlyCheckOut, true);
  assert.equal(stripeState.createdRefunds.length, 1);
  assert.equal(stripeState.createdRefunds[0].opts.idempotencyKey, "early_checkout_refund_bk_early");
  // ~1500 cents refunded (allow +/-25 cents for 1-minute clock boundary)
  assert.ok(
    Math.abs(stripeState.createdRefunds[0].params.amount - 1500) <= 30,
    `Expected ~1500 cents refund, got ${stripeState.createdRefunds[0].params.amount}`
  );

  const updated = fakeDb.readRaw("bookings/bk_early");
  assert.equal(updated.status, "completed");
  assert.equal(updated.escrowStatus, "held"); // Held so worked portion is released by autoReleaseEscrowCron!
  assert.equal(updated.earlyCheckOutRefunded, true);
  assert.ok(updated.caregiverPayout > 11 && updated.caregiverPayout < 13);
});

// ---------------------------------------------------------------------------
// 4. autoReleaseEscrowCron Integration Tests
// ---------------------------------------------------------------------------

test("autoReleaseEscrowCron — releases completed shift >24h to Connect account, increments loyalty hours, and blocks restricted accounts safely", async () => {
  fakeDb.reset();
  stripeState.reset();

  // Paid PaymentIntent on Stripe
  stripeState.paymentIntents.set("pi_done_1", {
    id: "pi_done_1",
    status: "succeeded",
    currency: "eur",
    amount: 3150,
    amount_received: 3150,
    latest_charge: "ch_done_1",
  });
  stripeState.paymentIntents.set("pi_blocked_1", {
    id: "pi_blocked_1",
    status: "succeeded",
    currency: "eur",
    amount: 3150,
    amount_received: 3150,
    latest_charge: "ch_blocked_1",
  });

  // Caregiver 1: Ready Connect account
  fakeDb.seed("caregivers/cg_ready", {
    name: "Elena Ready",
    stripeAccountId: "acct_ready",
    isKycVerified: true,
    transfersCapabilityStatus: "active",
  });

  // Caregiver 2: Restricted Connect account (transfers inactive)
  fakeDb.seed("caregivers/cg_restricted", {
    name: "Pedro Restricted",
    stripeAccountId: "acct_restricted",
    isKycVerified: false,
    transfersCapabilityStatus: "inactive",
  });
  stripeState.accounts.set("acct_restricted", {
    id: "acct_restricted",
    details_submitted: true,
    charges_enabled: true,
    payouts_enabled: false,
    capabilities: { transfers: "inactive" },
  });

  const threeDaysAgo = new Date(Date.now() - 72 * 3600 * 1000);
  const pastDay = formatYmdMadrid(threeDaysAgo);
  const onTimeMorningCheckIn = new Date(`${pastDay}T09:02:00Z`); // 10:02 CET in Europe/Madrid
  const onTimeAfternoonCheckIn = new Date(`${pastDay}T13:02:00Z`); // 14:02 CET in Europe/Madrid

  fakeDb.seed("bookings/bk_release_ok", {
    id: "bk_release_ok",
    clientId: "fam_1",
    caregiverId: "cg_ready",
    day: pastDay,
    slot: "10:00-12:00",
    status: "completed",
    escrowStatus: "held",
    paymentStatus: "paid",
    paymentIntentId: "pi_done_1",
    transferGroup: "booking_grp_1",
    cost: 30,
    caregiverCommissionRate: 0.18,
    caregiverCommissionAmount: 5.4,
    caregiverPayout: 24.6,
    checkInTime: FakeTimestamp.fromDate(onTimeMorningCheckIn),
  });

  fakeDb.seed("bookings/bk_release_blocked", {
    id: "bk_release_blocked",
    clientId: "fam_1",
    caregiverId: "cg_restricted",
    day: pastDay,
    slot: "14:00-16:00",
    status: "completed",
    escrowStatus: "held",
    paymentStatus: "paid",
    paymentIntentId: "pi_blocked_1",
    transferGroup: "booking_grp_2",
    cost: 30,
    caregiverCommissionRate: 0.18,
    caregiverCommissionAmount: 5.4,
    caregiverPayout: 24.6,
    checkInTime: FakeTimestamp.fromDate(onTimeAfternoonCheckIn),
  });

  await backend.autoReleaseEscrowCron({});

  // 1) Ready caregiver received exact transfer of 2460 cents & hours incremented by 2
  assert.equal(stripeState.createdTransfers.length, 1);
  assert.equal(stripeState.createdTransfers[0].params.amount, 2460);
  assert.equal(stripeState.createdTransfers[0].params.destination, "acct_ready");
  assert.equal(stripeState.createdTransfers[0].opts.idempotencyKey, "auto_release_bk_release_ok");

  const releasedDoc = fakeDb.readRaw("bookings/bk_release_ok");
  assert.equal(releasedDoc.escrowStatus, "released_auto");

  const statsDoc = fakeDb.readRaw("client_caregiver_stats/fam_1_cg_ready");
  assert.equal(statsDoc.accumulatedHours, 2);

  // 2) Restricted caregiver transitioned to payout_blocked + admin_alerts created without crashing
  const blockedDoc = fakeDb.readRaw("bookings/bk_release_blocked");
  assert.equal(blockedDoc.escrowStatus, "payout_blocked");
  const alertsSnap = await fakeDb.collection("admin_alerts").get();
  assert.equal(alertsSnap.size, 1);
  assert.equal(alertsSnap.docs[0].data().type, "payout_blocked_connect_not_ready");
});

// ---------------------------------------------------------------------------
// 5. stripeWebhook Signature, Settlement, Deduplication, Underpayment & Disputes
// ---------------------------------------------------------------------------

test("stripeWebhook — rejects invalid signature (400), settles payment_intent.succeeded, deduplicates replays, blocks underpayment, and freezes charge.dispute.created", async () => {
  fakeDb.reset();
  stripeState.reset();

  // 1) Invalid signature -> HTTP 400
  stripeState.webhookSignatureValid = false;
  const badRes = createMockRes();
  await backend.stripeWebhook(
    { headers: { "stripe-signature": "bad_sig" }, rawBody: Buffer.from("{}") },
    badRes
  );
  assert.equal(badRes.statusCode, 400);

  // 2) Valid payment_intent.succeeded -> marks booking paid & escrow held
  stripeState.webhookSignatureValid = true;
  fakeDb.seed("bookings/bk_wh_1", {
    id: "bk_wh_1",
    clientId: "fam_wh",
    caregiverId: "cg_wh",
    day: "2026-12-22",
    slot: "10:00-12:00",
    status: "pendingPayment",
    paymentStatus: "pending",
    escrowStatus: "none",
    paymentIntentId: "pi_wh_1",
    cost: 30,
    clientFee: 1.5,
    clientFeeRate: 0.05,
    caregiverCommissionRate: 0.18,
    totalPaid: 31.5,
  });

  const paidPi = {
    id: "pi_wh_1",
    status: "succeeded",
    currency: "eur",
    amount: 3150,
    amount_received: 3150,
    metadata: { familyId: "fam_wh", bookingIds: "bk_wh_1" },
    latest_charge: {
      id: "ch_wh_1",
      payment_method_details: { type: "card" },
    },
  };
  stripeState.paymentIntents.set("pi_wh_1", paidPi);
  stripeState.nextWebhookEvent = {
    id: "evt_paid_1",
    type: "payment_intent.succeeded",
    data: { object: paidPi },
  };

  const okRes = createMockRes();
  await backend.stripeWebhook(
    { headers: { "stripe-signature": "valid_sig" }, rawBody: Buffer.from("{}") },
    okRes
  );
  assert.equal(okRes.statusCode, 200);

  const settledBooking = fakeDb.readRaw("bookings/bk_wh_1");
  assert.equal(settledBooking.status, "pending");
  assert.equal(settledBooking.paymentStatus, "paid");
  assert.equal(settledBooking.escrowStatus, "held");

  // 3) Replay of exact same event.id is deduplicated atomically
  const dupRes = createMockRes();
  await backend.stripeWebhook(
    { headers: { "stripe-signature": "valid_sig" }, rawBody: Buffer.from("{}") },
    dupRes
  );
  assert.equal(dupRes.statusCode, 200);
  assert.equal(dupRes.body.duplicate, true);

  // 4) Underpayment fraud attempt is blocked and logged to admin_alerts
  fakeDb.seed("bookings/bk_underpaid", {
    id: "bk_underpaid",
    clientId: "fam_wh",
    caregiverId: "cg_wh",
    day: "2026-12-23",
    slot: "10:00-12:00",
    status: "pendingPayment",
    paymentStatus: "pending",
    escrowStatus: "none",
    paymentIntentId: "pi_underpaid",
    cost: 60,
    clientFee: 1.5,
    clientFeeRate: 0.025,
    caregiverCommissionRate: 0.18,
    totalPaid: 61.5,
  });
  const underpaidPi = {
    id: "pi_underpaid",
    status: "succeeded",
    currency: "eur",
    amount: 1000,
    amount_received: 1000, // Only 10.00€ instead of 61.50€!
    metadata: { familyId: "fam_wh", bookingIds: "bk_underpaid" },
  };
  stripeState.paymentIntents.set("pi_underpaid", underpaidPi);
  stripeState.nextWebhookEvent = {
    id: "evt_underpaid_1",
    type: "payment_intent.succeeded",
    data: { object: underpaidPi },
  };
  const underRes = createMockRes();
  await backend.stripeWebhook(
    { headers: { "stripe-signature": "valid_sig" }, rawBody: Buffer.from("{}") },
    underRes
  );
  assert.equal(fakeDb.readRaw("bookings/bk_underpaid").status, "pendingPayment");
  assert.equal(fakeDb.readRaw("bookings/bk_underpaid").paymentStatus, "pending");

  // 5) charge.dispute.created freezes escrowStatus -> "stripe_disputed" and alerts admin
  stripeState.nextWebhookEvent = {
    id: "evt_dispute_1",
    type: "charge.dispute.created",
    data: {
      object: {
        id: "dp_1",
        payment_intent: "pi_wh_1",
        charge: "ch_wh_1",
        amount: 3150,
        currency: "eur",
        status: "needs_response",
        reason: "fraudulent",
      },
    },
  };
  const dispRes = createMockRes();
  await backend.stripeWebhook(
    { headers: { "stripe-signature": "valid_sig" }, rawBody: Buffer.from("{}") },
    dispRes
  );
  assert.equal(dispRes.statusCode, 200);
  assert.equal(fakeDb.readRaw("bookings/bk_wh_1").escrowStatus, "stripe_disputed");
  assert.ok(fakeDb.readRaw("admin_alerts/dispute_dp_1"));
});

test("autoReleaseEscrowCron — 24h dispute timeout subtracts prior earlyCheckOutRefundAmountCents to prevent double-refund failure", async () => {
  fakeDb.reset();
  stripeState.reset();

  stripeState.paymentIntents.set("pi_disp_partial", {
    id: "pi_disp_partial",
    status: "succeeded",
    currency: "eur",
    amount: 3150,
    amount_received: 3150,
  });

  fakeDb.seed("bookings/bk_disp_partial", {
    id: "bk_disp_partial",
    clientId: "fam_1",
    caregiverId: "cg_1",
    day: "2026-11-10",
    slot: "10:00-12:00",
    status: "completed",
    escrowStatus: "disputed",
    disputeEscalated: false,
    disputeOpenedAt: FakeTimestamp.fromMillis(Date.now() - 30 * 3600 * 1000), // 30h ago (>24h)
    paymentStatus: "paid",
    paymentIntentId: "pi_disp_partial",
    totalPaid: 31.5, // 3150 cents originally charged
    earlyCheckOutRefundAmountCents: 1500, // 15.00€ already refunded at early check-out
  });

  await backend.autoReleaseEscrowCron({});

  assert.equal(stripeState.createdRefunds.length, 1);
  // Only remaining 1650 cents (3150 - 1500) refunded!
  assert.equal(stripeState.createdRefunds[0].params.amount, 1650);
  assert.equal(
    stripeState.createdRefunds[0].opts.idempotencyKey,
    "dispute_timeout_refund_bk_disp_partial"
  );
  assert.equal(fakeDb.readRaw("bookings/bk_disp_partial").escrowStatus, "refunded");
});
