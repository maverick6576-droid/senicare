---
name: eldercare-user-psychology
description: >-
  Use this skill to analyze user psychology, emotional triggers, trust barriers,
  cognitive load, and behavioral friction across SeniCare's personas (families,
  older adults, and caregivers) and translate findings into concrete UX,
  microcopy, and product improvements.
---

# Elder-Care User Psychology & Behavioral UX Analyzer

Hiring someone to care for an aging parent is one of the highest-trust, highest-anxiety decisions a family makes. Apply this framework to audit and adapt every screen, flow, and message in SeniCare.

## 1. The Three SeniCare Personas & Psychological Drivers

| Persona | Primary Emotion | Core Fear | Primary Psychological Need |
| :--- | :--- | :--- | :--- |
| **Family Decision-Maker** (Adult child, 35–60) | Overwhelm, guilt, urgency | "What if I choose the wrong person and my parent gets hurt or neglected?" | **Instant verifiable trust**, transparency, control without micromanaging |
| **Older Adult / Senior** (65+) | Desire for dignity & autonomy | "I don't want to feel like a burden or break something by tapping wrong" | **Clarity, respect, calm pacing**, zero jargon, reversible actions |
| **Caregiver** (Cuidador/a) | Pride in care, economic stress | "Will I be paid on time, treated fairly, and safe in a stranger's home?" | **Fairness, payout predictability**, clear expectations, personal safety |

## 2. Six-Lens Psychological Screen Audit

When evaluating any flow (Onboarding, Search/Explore, Caregiver Profile, Booking & Checkout, Chat, Shift Tracking, Reviews), score 1–5 on each lens and fix anything scoring ≤ 3:

1. **Trust Architecture (Eliminating Stranger Danger)**
   - Surface verification proof *at the moment of decision* (ID verified, background check, verified reviews from real completed bookings, response time, completed hours).
   - Explain **how Stripe escrow/protection works** right next to the Pay button ("Tu pago queda protegido hasta confirmar el servicio").
2. **Cognitive Load & Hick's Law**
   - Limit each screen to **1 primary decision**. Break multi-field forms (onboarding, job posting, booking) into progressive steps with a clear progress bar ("Paso 2 de 3").
   - Use smart defaults (e.g., standard 2h–4h shift durations, quick-pick time chips instead of raw time pickers).
3. **Error Anxiety & Reversibility**
   - Older adults hesitate before tapping ambiguous buttons. Use explicit outcome-based labels: `"Confirmar reserva — 45 €"` instead of `"Continuar"` or `"Aceptar"`.
   - Clearly communicate cancellation safety before payment ("Cancelación gratuita hasta 24h antes").
4. **Empathetic Microcopy (Warm, Human, Dignified)**
   - Avoid cold/clinical or transactional language (`"Entidad"`, `"Usuario inválido"`, `"Error 500"`, `"Contratar personal"`).
   - Use warm, respectful Spanish/localized phrasing (`"Cuidadores verificados cerca de ti"`, `"Tu familiar está en buenas manos"`, `"No pudimos cargar los datos — inténtalo de nuevo"`).
5. **Peace-of-Mind Loops (Retention & Reassurance)**
   - Families stay loyal when anxiety drops automatically: shift check-in notification (with GPS/QR confirmation), brief end-of-shift care summary ("Todo bien hoy: paseo + medicación"), easy re-booking of a trusted caregiver in 2 taps.
6. **Caregiver Motivation & Safety**
   - Show exact net earnings *before* accepting a job (no hidden commission surprises).
   - Provide quick emergency/support access and clear client details so caregivers feel respected and protected.

## 3. Data-Driven Validation (`firebase_analytics`)

Never guess where users feel friction — instrument key psychological drop-off points in `firebase_analytics`:
- `onboarding_role_selected` -> `onboarding_completed`
- `caregiver_profile_viewed` (with `is_verified`, `review_count`) -> `chat_started`
- `booking_started` -> `checkout_opened` -> `payment_succeeded` / `payment_abandoned`
- `shift_checked_in` -> `review_submitted` -> `repeat_booking_created`

## 4. Output Format for Audits

When running a psychological UX audit, produce:
1. **Top Friction Moments** (Screen + Persona affected + Psychological trigger violated).
2. **Concrete Code/Copy Fixes** (exact file path, current text/layout -> improved version).
3. **Expected Impact** (Trust, Conversion, Retention, or Accessibility).
