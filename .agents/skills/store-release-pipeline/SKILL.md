---
name: store-release-pipeline
description: >-
  Use this skill to configure, connect, build, sign, and publish SeniCare to
  Google Play Console (Android) and Apple App Store Connect (iOS), including
  CI/CD automation from Windows via GitHub Actions and store review compliance.
---

# Google Play Console & App Store Release Pipeline (SeniCare)

End-to-end launch runbook for shipping `senicare` (Flutter + Firebase + Stripe) to Google Play and Apple App Store, optimized for a Windows dev workstation + GitHub Actions CI/CD.

## 1. Pre-Build Version & Identity Check

1. Verify `version: X.Y.Z+BUILD` in `pubspec.yaml` (increment `+BUILD` on every store upload).
2. Confirm unique production identifiers (never `com.example.*`):
   - Android: `applicationId` in `android/app/build.gradle.kts`
   - iOS: `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj/project.pbxproj`
3. Confirm Firebase config matches the production project (`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, `lib/firebase_options.dart`, `.firebaserc`).

## 2. Google Play Console (Android)

### Local / CI Release Build
- Build a signed **Android App Bundle (AAB)** — Google Play rejects APKs for new releases:
  ```powershell
  flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/android
  ```
- Verify `android/app/build.gradle.kts` uses `release.keystore` via environment variables or untracked `android/key.properties` (NEVER hardcode keystore passwords in git).
- Upload debug symbols (`build/symbols/android`) to Google Play Console & Firebase Crashlytics.

### Connecting Google Play Console Automatically (API / CI)
1. In **Google Cloud Console**, enable **Google Play Android Developer API** and create a Service Account JSON key.
2. In **Google Play Console -> Users and permissions**, invite that service account with **Release to testing tracks / Manage production releases** permissions.
3. Store the JSON key in GitHub Secrets (`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`) and base64 keystore secrets (`ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`).
4. Automate uploads in `.github/workflows/` using `r0adkll/upload-google-play@v1` (or Fastlane `supply`) targeting `internal` -> `production`.
   - *Note*: The very first AAB for a brand-new app must be uploaded once manually in Play Console to initialize the package name before API uploads succeed.

### Google Play Review Checklist
- **Target API level**: `targetSdk` meets current Google Play requirement (API 35+).
- **Data Safety Form**: Declare Location (precise/approximate), Camera/Photos (ID/profile), Audio (voice notes), Financial info (handled by Stripe), Messages, Crash logs & Analytics.
- **Permissions Justification**: Explain `ACCESS_FINE_LOCATION` (caregiver map & shift check-in), `CAMERA` (ID verification & QR check-in), `RECORD_AUDIO` (chat voice messages). Remove any unused permissions from `AndroidManifest.xml`.
- **Account Deletion**: Provide both an in-app deletion button AND a public web deletion URL.

## 3. Apple App Store Connect (iOS from Windows)

Since this workstation runs Windows, build and upload iOS using **GitHub Actions `macos-latest`** (or Codemagic / Xcode Cloud):

### Connecting App Store Connect API
1. In **App Store Connect -> Users and Access -> Integrations -> App Store Connect API**, generate an API Key (`.p8`), noting **Key ID** and **Issuer ID**.
2. Create Distribution Certificate (`.p12`) and App Store Provisioning Profile (or manage automatically via Fastlane `match`).
3. Store in GitHub Secrets: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`, `IOS_DIST_CERT_BASE64`, `IOS_DIST_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`.
4. CI workflow steps on `macos-latest`:
   ```yaml
   - run: flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios --export-options-plist=ios/ExportOptions.plist
   - run: xcrun altool --upload-app -f build/ios/ipa/*.ipa --type ios --apiKey $KEY_ID --apiIssuer $ISSUER_ID
   ```

### Apple App Review Anti-Rejection Checklist
- **`ios/Runner/Info.plist`**: Ensure clear, human-readable Spanish/English purpose strings for every used permission (`NSLocationWhenInUseUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSMicrophoneUsageDescription`, `NSUserTrackingUsageDescription` if applicable).
- **`ios/Runner/PrivacyInfo.xcprivacy`**: Declare all Apple Required Reason APIs (`UserDefaults` from `shared_preferences`, file timestamps, disk space, etc.).
- **Sign in with Apple**: `google_sign_in` is present, so `sign_in_with_apple` MUST be prominently displayed and working on iOS (Guideline 4.8).
- **Stripe Justification in App Review Notes**: Explicitly state that SeniCare facilitates **in-person physical elder-care services** (exempt from Apple IAP under Guideline 3.1.3(e)).
- **Reviewer Demo Account**: Provide a working demo email/password (or bypass OTP test code) in App Review Information so reviewers can test booking, chat, and caregiver flows end-to-end.
- **In-App Account Deletion**: Mandatory under Guideline 5.1.1(v).

## 4. Production Launch Day Sequence (T-24h -> Live)

1. Deploy `firestore.indexes.json`, `firestore.rules`, and `storage.rules` (`firebase deploy --only firestore,storage`).
2. Set live Stripe secrets in Firebase Secret Manager and deploy Cloud Functions (`firebase deploy --only functions`).
3. Configure Stripe **Live** webhook endpoint pointing to the production Cloud Function URL and verify signing secret matches.
4. Smoke test on physical Android & iOS (TestFlight / Internal Testing): Sign up, Onboarding, Caregiver search, Chat, Real €1 Stripe test booking + refund, Push notification, Crashlytics test event.
5. Submit to Google Play Production & App Store Review.
