---
name: appsec-production-shield
description: >-
  Use this skill to perform security audits, fix vulnerabilities, protect PII
  and credentials, harden Firebase rules and Cloud Functions, and verify mobile
  app security before deploying SeniCare to production.
---

# AppSec Production Shield (SeniCare)

SeniCare handles sensitive family data, elder care schedules, GPS locations, identity verification documents (OCR/ID photos), chat messages, and Stripe payments. Run this security shield before every production release.

## 1. Immediate P0 Secret & Repository Hygiene

Check these **first** on every pre-release audit:
1. **Bundled `.env` in `pubspec.yaml`**: `pubspec.yaml` currently lists `- .env` under `flutter.assets`. Anything bundled in Flutter assets is **publicly extractable** by unzipping the APK/IPA/Web bundle.
   - Verify `.env` contains ONLY public client values (e.g., `STRIPE_PUBLISHABLE_KEY` `pk_*`).
   - If ANY secret (`sk_*`, `whsec_*`, admin keys, private API keys) exists in `.env`, remove it immediately, rotate the key, and move it to Firebase Secret Manager.
2. **Service Account & Signing Keys in Workspace**:
   - Inspect `firebase-admin.json`, `firebase-key.json`, and `android/app/release.keystore`.
   - Ensure all three are in `.gitignore` and **NOT** tracked in git (`git ls-files firebase-admin.json firebase-key.json android/app/release.keystore`).
   - If any key was ever committed to git history, rotate the credential immediately and scrub history / revoke old keys in Google Cloud IAM.
3. **Debug Artifacts**: Remove test scripts/credentials (`create_user.py`, `db_sample.json`, `screenshot*.png`) from production hosting/public bundles and ensure they contain no real user data.

## 2. Firebase Security Rules (`firestore.rules` & `storage.rules`)

- **Mandatory Delegation**: Any edit to `firestore.rules` MUST be delegated to the `firestore-rules-author` subagent and audited with `firebase-security-rules-auditor`.
- Verify these SeniCare-specific invariants:
  - **No privilege escalation**: Users cannot set or modify their own `role` (`admin`, `verified`, `isVerifiedCaregiver`), `rating`, `walletBalance`, or `paymentStatus` fields in Firestore. Admin privileges must rely on Firebase Auth Custom Claims (`request.auth.token.admin == true`) or server-only collections.
  - **Strict document ownership**: Bookings, chats, reports, and timesheets are readable/writable ONLY by the authenticated `clientId`, `caregiverId`, or `admin`.
  - **Identity & KYC documents in `storage.rules`**: ID card photos/selfies must be write-once by owner, NEVER publicly readable (`allow read: if false` except admin / signed server URLs), with strict `contentType` (`image/*`, `application/pdf`) and max size (`<= 10MB`) enforcement.
  - **Default deny**: Confirm fallback rules deny all unmatched paths.

## 3. Cloud Functions & API Hardening (`functions/index.js`)

- Every callable function must verify `if (!request.auth) throw new HttpsError('unauthenticated', ...)` and authorize ownership against Firestore before reading/mutating records.
- Enable **Firebase App Check** enforcement (`enforceAppCheck: true`) on sensitive callables (payments, identity verification, admin endpoints) once Play Integrity & App Attest are configured.
- Validate and sanitize all inputs; never interpolate user input into HTML/PDF/query paths without escaping.
- Never return internal stack traces or raw Stripe/GCP error internals to clients.

## 4. Mobile & Privacy Compliance (GDPR / LOPDGDD / Store Mandates)

- **Android**: Enable R8 code shrinking & obfuscation (`isMinifyEnabled = true`, `isShrinkResources = true`) in `android/app/build.gradle.kts` release build; verify `proguard-rules.pro` keeps Firebase/Stripe/ML Kit classes; disable `usesCleartextTraffic`.
- **iOS**: Enforce ATS (HTTPS only), verify `Runner.entitlements` contains only required capabilities, keep `PrivacyInfo.xcprivacy` accurate.
- **2FA / OTP**: Verify TOTP (`otp`/`base32`) secrets are stored securely and verified server-side, never solely client-side.
- **Account & Data Deletion**: Confirm an in-app **Delete Account** flow exists (and a web URL for Google Play) that deletes/anonymizes user Auth, Firestore profile, Storage files, and cancels active subscriptions/holds as required by Apple & Google Play.

## 5. Security Verification Command Checklist

```powershell
git ls-files .env firebase-admin.json firebase-key.json android/app/release.keystore
```
Confirm zero sensitive keys are tracked, rules pass emulator/audit checks, and no `sk_live_` / `sk_test_` / `BEGIN PRIVATE KEY` strings appear under `lib/` or `public/`.
