import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:senicare/core/globals.dart';
import 'package:senicare/core/observability_service.dart';
import 'package:senicare/l10n/app_localizations.dart';

class ConfigNotifier extends ChangeNotifier {
  static const String _prefSeniorModeKey = 'senicare_senior_mode';
  static const String _prefLocaleKey = 'senicare_locale_code';

  bool seniorMode = false;
  Locale locale = const Locale('es', 'ES');
  bool pendingCaregiverTutorial = false;
  bool pendingClientTutorial = false;
  bool _prefsLoaded = false;

  bool get hasLoadedPreferences => _prefsLoaded;

  static Locale _localeFromCode(String? code) {
    switch (code?.toLowerCase()) {
      case 'en':
        return const Locale('en', 'US');
      case 'ca':
        return const Locale('ca', 'ES');
      case 'es':
      default:
        return const Locale('es', 'ES');
    }
  }

  /// Carga preferencias locales persistidas (`SharedPreferences`) al arrancar.
  Future<void> loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSenior = prefs.getBool(_prefSeniorModeKey);
      final savedLang = prefs.getString(_prefLocaleKey);
      bool changed = false;
      if (savedSenior != null && savedSenior != seniorMode) {
        seniorMode = savedSenior;
        changed = true;
      }
      if (savedLang != null) {
        final nextLocale = _localeFromCode(savedLang);
        if (nextLocale.languageCode != locale.languageCode) {
          locale = nextLocale;
          changed = true;
        }
      }
      _prefsLoaded = true;
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('ConfigNotifier.loadPreferences skipped: $e');
    }
  }

  Future<void> toggleSeniorMode(bool value) async {
    seniorMode = value;
    notifyListeners();
    ObservabilityService.setUserContext(seniorMode: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefSeniorModeKey, value);
    } catch (_) {}
    await _syncToFirestore({'seniorMode': value});
  }

  Future<void> setLocale(Locale nextLocale) async {
    final normalized = _localeFromCode(nextLocale.languageCode);
    if (!AppLocalizations.supportedLocales
        .any((l) => l.languageCode == normalized.languageCode)) {
      return;
    }
    locale = normalized;
    notifyListeners();
    ObservabilityService.logEvent(
      'language_changed',
      parameters: {'language_code': normalized.languageCode},
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLocaleKey, normalized.languageCode);
    } catch (_) {}
    await _syncToFirestore({'preferredLocale': normalized.languageCode});
  }

  Future<void> _syncToFirestore(Map<String, dynamic> fields) async {
    if (!useFirebaseBackend || Firebase.apps.isEmpty) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(fields, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Requests [MainLayout] to open the caregiver interactive tutorial.
  void triggerCaregiverTutorial() {
    pendingCaregiverTutorial = true;
    notifyListeners();
  }

  void consumeCaregiverTutorialRequest() {
    pendingCaregiverTutorial = false;
  }

  /// Requests [MainLayout] to open the client (family) interactive tutorial.
  void triggerClientTutorial() {
    pendingClientTutorial = true;
    notifyListeners();
  }

  void consumeClientTutorialRequest() {
    pendingClientTutorial = false;
  }
}
