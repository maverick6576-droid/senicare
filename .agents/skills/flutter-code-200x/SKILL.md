---
name: flutter-code-200x
description: >-
  Use this skill when auditing, refactoring, optimizing, or writing high-quality
  Dart/Flutter code and Node 22 Firebase Cloud Functions in SeniCare to eliminate
  bugs, memory leaks, unnecessary rebuilds, and production crashes.
---

# Flutter & Cloud Functions 200% Code Quality Protocol

Apply this workflow whenever improving code quality, reviewing PRs, or hardening modules in `lib/` and `functions/`.

## 1. Baseline Diagnostics (Always Run First)

```powershell
dart analyze
flutter test
node --check functions/index.js
```

Treat **all** analyzer errors and high-risk warnings (`use_build_context_synchronously`, `cancel_subscriptions`, `close_sinks`, `unawaited_futures`) as defects to fix.

## 2. Flutter / Dart Hardening Checklist (`lib/`)

### State Management (`provider` & `lib/core/notifiers/`)
- Replace broad `context.watch<T>()` inside large screen `build()` methods with `context.select<T, R>(...)` or scoped `Selector` widgets so unrelated updates do not rebuild entire screens.
- Use `context.read<T>()` inside callbacks (`onPressed`, `initState`), never `watch`.
- Keep business logic and Firestore/HTTP calls inside `lib/repositories/` and `lib/core/` — never directly inside widget `build()` or anonymous button callbacks.

### Async, Lifecycle & Memory Safety
- Guard every `BuildContext` usage after an `await` with `if (!mounted) return;` (or `if (!context.mounted) return;`).
- Dispose every `TextEditingController`, `ScrollController`, `FocusNode`, `AnimationController`, `Timer`, and `StreamSubscription` in `dispose()`.
- Wrap all external I/O (Firestore, Storage, HTTP, Cloud Functions, ML Kit, Geolocator) in `try / on FirebaseException / catch` with explicit `.timeout(...)` and user-friendly localized error states — never leave spinners hanging forever.
- Protect mutating buttons (Pay, Book, Send, Delete) with an `_isSubmitting` guard to prevent double-submission on rapid taps.

### Performance & Resilience
- Use `const` constructors aggressively on static widgets and icons.
- Use `ListView.builder` / `SliverList` with `itemExtent` or `cacheExtent` for feeds, chats, bookings, and caregiver lists.
- Use `CachedNetworkImage` with `memCacheWidth` / `memCacheHeight` for profile photos and uploaded images.
- Check connectivity via `connectivity_plus` and show graceful offline banners/retry actions instead of silent failures.
- Ensure all crashes and non-fatal errors report to `FirebaseCrashlytics.instance.recordError(e, stack, fatal: false)` without logging PII.

## 3. Cloud Functions Hardening Checklist (`functions/index.js`, Node 22)

- **Validate every input** at the top of callable and HTTP functions (types, ranges, required fields, string length bounds); throw `HttpsError('invalid-argument', ...)` early.
- **Bound Firestore queries** with `.limit(...)` and required composite indexes (`firestore.indexes.json`).
- **Atomic multi-document writes**: Use `db.runTransaction` or `db.batch()` for bookings, timesheets, wallet/payout updates, and status transitions.
- **Structured logging**: Use `firebase-functions/logger` (`logger.info`, `logger.warn`, `logger.error`) with correlation IDs (`bookingId`, `uid`, `eventId`); never log secrets, tokens, or full PII.
- **Idempotency**: Design retries safely — Cloud Functions v2 / HTTP webhooks can deliver at-least-once.

## 4. High-ROI Testing Strategy

Prioritize tests that protect revenue and core user flows:
1. **Unit tests**: Models serialization (`fromJson`/`toJson`), pricing/fee calculations, booking state machine transitions.
2. **Repository tests**: Use existing `fake_cloud_firestore` and `firebase_auth_mocks` in `test/`.
3. **Widget tests**: Critical forms (auth, booking checkout, caregiver profile, chat input) including error & loading states.
4. **Backend scripts**: Run `functions/stripe_test.js` and `functions/verify_finances.js` after any payment/booking backend change.

## 5. Refactoring Discipline

- Prefer small, surgical commits per module rather than sweeping rewrites right before launch.
- Delete dead code, unused imports, and leftover debug `print()` statements (`debugPrint` only where justified).
- Re-run `dart analyze` and `flutter test` after every refactor batch.
