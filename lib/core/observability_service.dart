import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Servicio centralizado de observabilidad (Crashlytics + Analytics + captura global).
class ObservabilityService {
  static bool _initialized = false;
  static bool _crashlyticsReady = false;
  static bool _analyticsReady = false;
  static final List<String> _recentEventLog = [];

  static bool get isInitialized => _initialized;
  static bool get isCrashlyticsActive => _crashlyticsReady;
  static bool get isAnalyticsActive => _analyticsReady;

  @visibleForTesting
  static List<String> get recentEventLog => List.unmodifiable(_recentEventLog);

  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _crashlyticsReady = false;
    _analyticsReady = false;
    _recentEventLog.clear();
  }

  static bool get _supportsCrashlytics =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _supportsAnalytics =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static void _appendLog(String entry) {
    _recentEventLog.add(entry);
    if (_recentEventLog.length > 50) {
      _recentEventLog.removeAt(0);
    }
  }

  /// Inicializa Crashlytics y Analytics de forma segura cuando Firebase está operativo.
  static Future<void> initialize({required bool firebaseReady}) async {
    _initialized = true;
    _crashlyticsReady = false;
    _analyticsReady = false;

    if (!firebaseReady || Firebase.apps.isEmpty) {
      return;
    }

    if (_supportsCrashlytics) {
      try {
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(kReleaseMode);
        _crashlyticsReady = true;
      } catch (e) {
        debugPrint('ObservabilityService: Crashlytics init skipped ($e)');
      }
    }

    if (_supportsAnalytics) {
      try {
        await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
        _analyticsReady = true;
      } catch (e) {
        debugPrint('ObservabilityService: Analytics init skipped ($e)');
      }
    }
  }

  /// Observer de navegación para `MaterialApp` si Analytics está disponible.
  static NavigatorObserver? get analyticsObserver {
    if (!_analyticsReady || Firebase.apps.isEmpty || !_supportsAnalytics) {
      return null;
    }
    try {
      return FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance);
    } catch (_) {
      return null;
    }
  }

  /// Registra excepciones del framework Flutter en Crashlytics y logs.
  static void recordFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Uncaught FlutterError: ${details.exceptionAsString()}');
    _appendLog('flutter_error:${details.exceptionAsString()}');
    if (_crashlyticsReady) {
      try {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      } catch (e) {
        debugPrint('Crashlytics recordFlutterFatalError failed: $e');
      }
    }
  }

  /// Registra errores asíncronos no capturados de plataforma/isolate.
  static bool recordPlatformError(Object error, StackTrace stack) {
    debugPrint('Uncaught PlatformError: $error');
    _appendLog('platform_error:$error');
    if (_crashlyticsReady) {
      try {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } catch (e) {
        debugPrint('Crashlytics recordError failed: $e');
      }
    }
    return true;
  }

  /// Registra una excepción controlada (no fatal) para diagnóstico en producción.
  static Future<void> recordNonFatalError(
    Object error,
    StackTrace stack, {
    String? reason,
  }) async {
    debugPrint('NonFatalError${reason != null ? ' [$reason]' : ''}: $error');
    _appendLog('non_fatal:${reason ?? 'error'}:$error');
    if (_crashlyticsReady) {
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          reason: reason,
          fatal: false,
        );
      } catch (_) {}
    }
  }

  /// Registra un evento analítico de producto (reservas, búsqueda, errores de red, etc.).
  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    _appendLog('event:$name');
    if (!_analyticsReady) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (_) {}
  }

  /// Asocia contexto de usuario anónimo (sin PII sensible) a Crashlytics/Analytics.
  static Future<void> setUserContext({
    String? userId,
    String? role,
    bool? seniorMode,
  }) async {
    final sanitizedId = userId?.trim() ?? '';
    _appendLog('user_context:${sanitizedId.isEmpty ? "anon" : "set"}:${role ?? "none"}');
    if (_crashlyticsReady) {
      try {
        await FirebaseCrashlytics.instance.setUserIdentifier(sanitizedId);
        if (role != null) {
          await FirebaseCrashlytics.instance.setCustomKey('user_role', role);
        }
        if (seniorMode != null) {
          await FirebaseCrashlytics.instance.setCustomKey('senior_mode', seniorMode);
        }
      } catch (_) {}
    }
    if (_analyticsReady) {
      try {
        await FirebaseAnalytics.instance
            .setUserId(id: sanitizedId.isEmpty ? null : sanitizedId);
        if (role != null) {
          await FirebaseAnalytics.instance
              .setUserProperty(name: 'user_role', value: role);
        }
      } catch (_) {}
    }
  }
}
