# SeniCare (Grandpa Care) — Workspace Agent Constitution

This repository is **SeniCare**, a production Flutter + Firebase + Stripe elder-care marketplace connecting families, older adults, and caregivers across Android, iOS, and Web.

## Mandatory Skill Activation Map

Before executing work in any of the domains below, read and follow the corresponding workspace skill under `.agents/skills/`:

1. **Planning & Multi-Agent Coordination** -> `.agents/skills/mission-control-orchestrator/SKILL.md`
2. **Code Quality, Refactoring & Performance (Flutter + Node 22)** -> `.agents/skills/flutter-code-200x/SKILL.md`
3. **Stripe Payments, Webhooks & Financial Logic** -> `.agents/skills/stripe-payment-guardian/SKILL.md`
4. **Visual UI, Design System & Responsiveness** -> `.agents/skills/senicare-ui-polish/SKILL.md`
5. **Security, Secrets, PII & Firebase Rules** -> `.agents/skills/appsec-production-shield/SKILL.md`
6. **User Psychology, Trust & Behavioral UX** -> `.agents/skills/eldercare-user-psychology/SKILL.md`
7. **Google Play Console & Apple App Store Publishing** -> `.agents/skills/store-release-pipeline/SKILL.md`
8. **Business Plan, Viability & Profit Projections** -> `.agents/skills/marketplace-business-strategist/SKILL.md`

## Non-Negotiable Production Guardrails

- **Firestore Security Rules**: NEVER edit `firestore.rules` directly in the main agent — ALWAYS delegate to the `firestore-rules-author` subagent and audit with `firebase-security-rules-auditor`.
- **Zero Secret Leakage**: Never put `sk_live_`, `sk_test_`, `whsec_`, or service account credentials in `lib/`, `public/`, or bundled Flutter assets (including `.env` if bundled in `pubspec.yaml`).
- **Server-Authoritative Money**: All pricing, platform fees, refunds, and payouts MUST be calculated and verified server-side in `functions/index.js` using integer cents and idempotency keys, with webhook-verified state transitions.
- **Accessibility & Trust First**: Every UI change must respect ≥ 48dp touch targets, ≥ 4.5:1 contrast, dynamic text scaling without overflow, and empathetic Spanish/localized copy suited for stressed families and older adults.
- **Verify Before Done**: Always run `dart analyze` (0 errors) and relevant `flutter test` / `functions` verification scripts before reporting completion.
