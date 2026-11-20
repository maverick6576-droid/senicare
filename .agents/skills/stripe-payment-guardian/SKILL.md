---
name: stripe-payment-guardian
description: >-
  Use this skill whenever designing, auditing, modifying, or testing Stripe
  payments, PaymentIntents, Stripe Connect payouts, webhooks, refunds, pricing
  calculations, or payment UI in SeniCare (lib/core/stripe*, lib/screens/pay*,
  functions/index.js).
---

# Stripe Payment Guardian (Financial-Grade Protocol)

Payments are zero-tolerance for bugs. Follow every invariant below before shipping any change touching money, bookings, fees, or payouts.

## 1. Non-Negotiable Financial Invariants

1. **Server-Authoritative Pricing ONLY**:
   - The Flutter client NEVER dictates the final charge amount, platform fee, tax, or currency.
   - `functions/index.js` must fetch the authoritative hourly rate, duration, caregiver tier, and booking record from Firestore, compute totals server-side, and create the Stripe `PaymentIntent` / `CheckoutSession`.
2. **Integer Minor Units Only**:
   - Compute all money values in integer cents (e.g., `1550` for `15.50 EUR`). Never use floating-point addition/multiplication for ledger balances or fee splits; round explicitly once (`Math.round`) at percentage boundaries.
3. **Idempotency Everywhere**:
   - Pass deterministic `idempotencyKey` (e.g., `pi_booking_${bookingId}_v${attempt}`, `transfer_${bookingId}`, `refund_${bookingId}`) on every mutating Stripe API call (`paymentIntents.create`, `transfers.create`, `refunds.create`).
4. **Webhook-Driven Truth**:
   - Never mark a booking as `paid` solely because the client `presentPaymentSheet()` resolved. The client may lose connectivity right after 3DS/SCA.
   - Treat Stripe webhooks (`payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`, `charge.dispute.created`, `account.updated`) as the source of truth.
5. **Strict Webhook Signature & Deduplication**:
   - Verify every webhook with `stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret)`. Reject missing/invalid signatures with `400`.
   - Inside a Firestore transaction, check and write `processed_stripe_events/{event.id}` before applying state transitions so duplicate webhook deliveries are 100% idempotent.

## 2. Key & Mode Hygiene (Test vs. Live)

- **Never** embed `sk_live_`, `sk_test_`, or `whsec_` anywhere in `lib/`, `assets/`, or a bundled `.env` file.
- Store Stripe secret key & webhook secret in **Firebase Secret Manager** (`defineSecret('STRIPE_SECRET_KEY')`, `defineSecret('STRIPE_WEBHOOK_SECRET')`), never hardcoded or in committed JSON.
- Only the **publishable key** (`pk_test_` / `pk_live_`) belongs in client config, and it must strictly match the backend mode (mixing `pk_live_` with `sk_test_` causes instant checkout failures).
- Verify 3D Secure / Strong Customer Authentication (SCA) works for European cards (PSD2) via `flutter_stripe` PaymentSheet & `flutter_stripe_web`.

## 3. Marketplace / Connect & Edge Cases

Audit and handle every lifecycle transition explicitly:
- **Booking cancellation**: Define clear refund policy windows (full vs. partial refund, cancellation fee) enforced server-side.
- **Caregiver payouts (Connect)**: Verify caregiver onboarding status (`charges_enabled`, `payouts_enabled`) before allowing bookings or triggering transfers.
- **Disputes / Chargebacks**: On `charge.dispute.created`, freeze related payout, flag booking in Firestore, and alert admin.
- **Double-charge prevention**: Check booking `paymentStatus` inside a Firestore transaction before creating a new `PaymentIntent`; reuse an existing open `PaymentIntent` if still valid.
- **Store Compliance (Apple & Google Play)**: In-person elder care is a real-world physical service, which qualifies for Stripe under Apple App Store Guideline 3.1.3(e) and Google Play Payments Policy. Ensure NO purely digital features (e.g., digital badges or profile boosts) are sold via Stripe without using native IAP.

## 4. Verification Protocol

Before approving any Stripe change:
1. Audit `functions/index.js` and `lib/core/stripe*` against Sections 1–3.
2. Run payment verification suites:
   ```powershell
   node functions/stripe_test.js
   node functions/verify_finances.js
   ```
3. Verify live/staging webhook delivery via Stripe CLI (`stripe listen --forward-to ...`) or Stripe Dashboard (or the official Stripe MCP plugin once enabled).
4. Confirm Firestore audit trail records: `paymentIntentId`, `amountCents`, `currency`, `platformFeeCents`, `status`, `updatedAt`.
