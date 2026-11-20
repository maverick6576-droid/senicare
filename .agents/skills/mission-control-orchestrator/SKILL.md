---
name: mission-control-orchestrator
description: >-
  Use this skill to plan work, decompose complex goals, coordinate multiple
  agents or subagents, manage parallel execution without merge conflicts, and
  enforce Go/No-Go production release gates for SeniCare (Grandpa Care).
---

# Mission Control Orchestrator (SeniCare)

Coordinate planning, prioritization, and multi-agent execution so changes ship fast without breaking payments, security, or UX.

## 1. Production Triage Framework (24h Launch Mode)

Classify every task before writing code:
- **P0 — Release Blocker**: Data leaks, broken Stripe payments/webhooks, crashes on startup/login/booking, store rejection triggers (missing privacy strings, missing account deletion, debug signing, `firestore.rules` holes). **Fix first.**
- **P1 — High Impact**: Core UX friction in booking/chat/onboarding, unhandled async errors, missing loading/empty states, slow screens, incomplete analytics on conversion steps. **Fix second.**
- **P2 — Post-Launch Polish**: Nice-to-have animations, secondary refactors, non-critical feature ideas. **Defer until v1.0.1.**

## 2. Agent Routing Matrix

Choose the leanest execution model that fits the scope:

| Task Type | Execution Mode | Mandatory Specialist / Skill |
| :--- | :--- | :--- |
| Single targeted fix (1–3 files) | Direct in main agent | Load the matching `.agents/skills/*` |
| Deep read-only codebase audit | `research` subagent | Read-only exploration; return file paths + line numbers |
| Any edit to `firestore.rules` | `firestore-rules-author` subagent | **Mandatory** + verify with `firebase-security-rules-auditor` |
| Accessibility & senior-usability audit | `flutter_a11y_agent` subagent | Combine with `senicare-ui-polish` & `eldercare-user-psychology` |
| Live Web UI inspection / E2E flow | `browser` subagent | Verify deployed or local web build visually |
| 3+ independent workstreams (e.g., Security + Stripe + UI + Release) | `swarm` or `run_workflow` | Assign **disjoint file ownership** per worker |

## 3. Multi-Agent Parallel Execution Rules

When running multiple agents/workers in parallel:
1. **Strict File Ownership**: Never assign two writers to the same file. Partition by boundary:
   - *Backend / Payments*: `functions/**`, `lib/core/stripe*`, `lib/screens/pay*`, `lib/widgets/pay*`
   - *Security & Rules*: `firestore.rules`, `storage.rules`, `.gitignore`, `pubspec.yaml` (assets check)
   - *UI / UX & Psychology*: `lib/core/theme.dart`, `lib/screens/**`, `lib/widgets/**`, `lib/l10n/**`
   - *Release & Stores*: `android/**`, `ios/**`, `.github/workflows/**`, `firebase.json`
2. **Contract-First Handoffs**: If Backend changes a Cloud Function payload or Firestore field, freeze the JSON schema in the plan *before* Frontend edits begin.
3. **Wave Structure**:
   - **Wave 1 (Audit)**: Parallel read-only audits (AppSec, Stripe, Code Quality, UX/Psychology, Store Readiness) producing a unified P0/P1/P2 punch list.
   - **Wave 2 (Fix P0s)**: Parallel isolated fixes with disjoint ownership.
   - **Wave 3 (Verify & Polish)**: Run full verification gates, fix P1s, prepare release build.

## 4. Definition of Done (Mandatory Gate)

No agent may declare a task complete until it reports:
1. Exact files modified.
2. Verification results:
   - Flutter: `dart analyze` (0 errors) + relevant `flutter test` pass.
   - Functions: `node --check functions/index.js` + `functions/stripe_test.js` / `verify_finances.js` (when payment logic touched).
   - Security: No secrets added, rules validated.
3. Remaining risks or deferred P2 items clearly listed.
