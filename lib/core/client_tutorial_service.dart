import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:senicare/core/core.dart';

/// Persists whether a client (family) user has already completed or exited the
/// interactive tutorial (both on the backend/mock profile and via a lightweight
/// per-user local flag file).
class ClientTutorialService {
  /// Allows headless widget tests to isolate runs from the local temp file.
  @visibleForTesting
  static bool useLocalFileStorage = true;

  static Future<bool> hasSeen(AuthNotifier auth) async {
    final userId = auth.currentUserId;
    if (userId == null || userId.isEmpty) return true;

    final isSharedMember = auth.isSharedFamilyMember;
    if (!isSharedMember && auth.currentClient?.hasSeenClientTutorial == true) {
      return true;
    }

    if (useLocalFileStorage && !kIsWeb && await _hasLocalFlag(userId)) {
      return true;
    }

    try {
      if (isSharedMember) {
        final seen =
            await DependencyInjection.families.hasSeenMemberTutorial(userId);
        if (seen) {
          if (useLocalFileStorage && !kIsWeb) {
            await _writeLocalFlag(userId);
          }
          return true;
        }
      } else {
        final fetched = await DependencyInjection.clients.getClient(userId);
        if (fetched != null) {
          auth.currentClient = fetched;
          if (fetched.hasSeenClientTutorial) {
            if (useLocalFileStorage && !kIsWeb) {
              await _writeLocalFlag(userId);
            }
            return true;
          }
        }
      }
    } catch (_) {
      // Fallback safely to profile/local state if offline
    }

    return false;
  }

  static Future<void> markSeen(AuthNotifier auth) async {
    final userId = auth.currentUserId;
    if (userId == null || userId.isEmpty) return;

    final isSharedMember = auth.isSharedFamilyMember;
    if (!isSharedMember) {
      final existing = auth.currentClient;
      if (existing != null && !existing.hasSeenClientTutorial) {
        auth.currentClient = existing.copyWith(hasSeenClientTutorial: true);
        auth.forceRefresh();
      }
    }

    if (useLocalFileStorage && !kIsWeb) {
      await _writeLocalFlag(userId);
    }

    try {
      if (isSharedMember) {
        await DependencyInjection.families
            .markMemberTutorialSeen(userId, seen: true);
      } else {
        await DependencyInjection.clients.updateClient(userId, {
          'clientTutorialSeen': true,
        });
      }
    } catch (_) {
      // Local flag already protects against immediate repeats offline
    }
  }

  static File _flagFileFor(String userId) {
    final safeId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${Directory.systemTemp.path}/senicare_cl_tutorial_$safeId.done');
  }

  static Future<bool> _hasLocalFlag(String userId) async {
    try {
      return await _flagFileFor(userId).exists();
    } catch (_) {
      return false;
    }
  }

  static Future<void> _writeLocalFlag(String userId) async {
    try {
      await _flagFileFor(userId).writeAsString('seen');
    } catch (_) {
      // Non-critical in sandboxed environments
    }
  }
}
