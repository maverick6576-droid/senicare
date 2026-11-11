import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:senicare/core/dependency_injection.dart';
import 'package:senicare/core/notifiers/auth_notifier.dart';

/// Persists whether a caregiver has already completed or dismissed the guided
/// tutorial, both locally on device and in the caregiver's backend profile.
class CaregiverTutorialService {
  /// Allows widget tests to bypass local disk storage so host Documents
  /// folders remain untouched and FakeAsync clocks do not block on OS file I/O.
  @visibleForTesting
  static bool useLocalFileStorage = true;

  static Future<File?> _flagFile(String userId) async {
    if (!useLocalFileStorage || kIsWeb || userId.trim().isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      return File(p.join(dir.path, 'senicare_cg_tutorial_$safeId.done'));
    } catch (_) {
      return null;
    }
  }

  /// Returns true if this user already dismissed or finished the tutorial on
  /// this device, failing closed (false) if local storage is unavailable.
  static Future<bool> hasSeenLocally(String userId) async {
    if (!useLocalFileStorage || kIsWeb || userId.trim().isEmpty) {
      return false;
    }
    try {
      final file = await _flagFile(userId);
      if (file == null) return false;
      return file.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Marks the caregiver tutorial as seen locally and on the user's profile.
  static Future<void> markSeen({
    required String userId,
    AuthNotifier? auth,
  }) async {
    if (userId.trim().isEmpty) return;

    if (useLocalFileStorage) {
      try {
        final file = await _flagFile(userId);
        if (file != null && !file.existsSync()) {
          file.writeAsStringSync('seen', flush: true);
        }
      } catch (_) {
        // Safe fallback in headless tests / restricted environments.
      }
    }

    try {
      await DependencyInjection.caregivers.updateProfile(
        userId,
        {'caregiverTutorialSeen': true},
      );
      if (auth != null && auth.currentUserId == userId) {
        final refreshed = await DependencyInjection.caregivers.getCaregiver(userId);
        if (refreshed != null && auth.currentUserId == userId) {
          auth.currentCaregiver = refreshed;
          auth.forceRefresh();
        }
      }
    } catch (e) {
      debugPrint('Could not persist caregiverTutorialSeen: $e');
    }
  }
}
