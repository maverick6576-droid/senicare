import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/interfaces/family_repository.dart';

class FirestoreFamilyRepository implements FamilyRepository {
  FirestoreFamilyRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _functionsOverride = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions? _functionsOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  @override
  Future<String?> resolveActiveFamilyId({
    required String uid,
    String? email,
    String? displayName,
    bool emailVerified = false,
  }) async {
    // 1. Leer users/{uid}.activeFamilyId
    try {
      final userSnap = await _db.collection('users').doc(uid).get();
      final activeFamilyId =
          userSnap.data()?['activeFamilyId']?.toString().trim();
      if (activeFamilyId != null && activeFamilyId.isNotEmpty) {
        final familyDoc =
            await _db.collection('clients').doc(activeFamilyId).get();
        if (familyDoc.exists) {
          final family = ClientProfile.fromFirestore(familyDoc);
          if (family.isMember(uid)) {
            return activeFamilyId;
          }
        }
      }
    } catch (_) {}

    // 2. Comprobar cuenta propia ya completada (`clients/{uid}`)
    try {
      final ownDoc = await _db.collection('clients').doc(uid).get();
      if (ownDoc.exists && (ownDoc.data()?['onboardingComplete'] == true)) {
        await _db.collection('users').doc(uid).set({
          'activeFamilyId': uid,
        }, SetOptions(merge: true));
        return uid;
      }
    } catch (_) {}

    // 3. Intentar auto-unión segura por email invitado en Cloud Functions
    final normalizedEmail = email?.trim().toLowerCase() ?? '';
    if (normalizedEmail.isNotEmpty && emailVerified) {
      try {
        final result = await _functions
            .httpsCallable('claimPendingFamilyInvite')
            .call<Map<String, dynamic>>({
          'displayName': displayName ?? '',
        });
        final claimedFamilyId = result.data['familyId']?.toString().trim();
        if (claimedFamilyId != null && claimedFamilyId.isNotEmpty) {
          return claimedFamilyId;
        }
      } catch (_) {
        // Silencioso: si no hay invitación o falla temporalmente, sigue al onboarding manual / código
      }
    }

    return null;
  }

  @override
  Future<FamilyInvite> createInvite({
    required String familyId,
    required String familyName,
    required FamilyRole role,
    String? invitedEmail,
    int maxUses = 5,
    Duration validFor = const Duration(days: 7),
  }) async {
    final result = await _functions
        .httpsCallable('createFamilyInvite')
        .call<Map<String, dynamic>>({
      'familyId': familyId,
      'familyName': familyName,
      'role': role.firestoreValue,
      if (invitedEmail != null && invitedEmail.trim().isNotEmpty)
        'invitedEmail': invitedEmail.trim().toLowerCase(),
      'maxUses': maxUses,
      'validHours': validFor.inHours,
    });
    return FamilyInvite.fromMap(
      result.data['code']?.toString() ?? '',
      Map<String, dynamic>.from(result.data),
    );
  }

  @override
  Future<List<FamilyInvite>> getActiveInvites(String familyId) async {
    final snap = await _db
        .collection('family_invites')
        .where('familyId', isEqualTo: familyId)
        .where('revoked', isEqualTo: false)
        .get();
    final invites = snap.docs
        .map((doc) => FamilyInvite.fromMap(doc.id, doc.data()))
        .where((i) => i.isActive)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return invites;
  }

  @override
  Future<void> revokeInvite({
    required String familyId,
    required String code,
  }) async {
    await _functions
        .httpsCallable('revokeFamilyInvite')
        .call<Map<String, dynamic>>({
      'familyId': familyId,
      'code': code.trim().toUpperCase(),
    });
  }

  @override
  Future<void> inviteByEmail({
    required String familyId,
    required String email,
    required FamilyRole role,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final ref = _db.collection('clients').doc(familyId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final emails = List<String>.from(
          (data['authorizedFamilyEmails'] as List<dynamic>? ?? [])
              .map((e) => e.toString()));
      if (!emails.any((e) => e.toLowerCase() == normalized)) {
        emails.add(normalized);
      }
      final roles = Map<String, dynamic>.from(
          data['familyEmailRoles'] as Map? ?? {});
      roles[normalized] = role.firestoreValue;
      tx.set(
        ref,
        {
          'authorizedFamilyEmails': emails,
          'familyEmailRoles': roles,
        },
        SetOptions(merge: true),
      );
    });
  }

  @override
  Future<void> removeEmailInvite({
    required String familyId,
    required String email,
  }) async {
    final normalized = email.trim().toLowerCase();
    final ref = _db.collection('clients').doc(familyId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final emails = (data['authorizedFamilyEmails'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.trim().toLowerCase() != normalized)
          .toList();
      final roles = Map<String, dynamic>.from(
          data['familyEmailRoles'] as Map? ?? {});
      roles.removeWhere((k, _) => k.trim().toLowerCase() == normalized);
      tx.update(ref, {
        'authorizedFamilyEmails': emails,
        'familyEmailRoles': roles,
      });
    });
  }

  @override
  Future<FamilyJoinResult> joinWithCode({
    required String uid,
    required String codeOrUrl,
    String? email,
    String? displayName,
  }) async {
    final code = FamilyInvite.extractInviteCode(codeOrUrl);
    if (code == null) {
      throw StateError('Introduce un código o enlace de invitación válido.');
    }
    final result = await _functions
        .httpsCallable('joinFamilyByCode')
        .call<Map<String, dynamic>>({
      'code': code,
      'displayName': displayName ?? '',
    });
    return FamilyJoinResult(
      familyId: result.data['familyId']?.toString() ?? '',
      familyName: result.data['familyName']?.toString() ?? 'Familia SeniCare',
      role: FamilyRole.fromString(result.data['role']),
      joinedVia: 'code',
      alreadyMember: result.data['alreadyMember'] == true,
    );
  }

  @override
  Future<void> updateMemberRole({
    required String familyId,
    required String memberUid,
    required FamilyRole newRole,
  }) async {
    await _functions
        .httpsCallable('updateFamilyMemberRole')
        .call<Map<String, dynamic>>({
      'familyId': familyId,
      'memberUid': memberUid,
      'role': newRole.firestoreValue,
    });
  }

  @override
  Future<void> removeMember({
    required String familyId,
    required String memberUid,
  }) async {
    await _functions
        .httpsCallable('removeFamilyMember')
        .call<Map<String, dynamic>>({
      'familyId': familyId,
      'memberUid': memberUid,
    });
  }

  @override
  Future<void> leaveFamily({
    required String familyId,
    required String uid,
  }) async {
    await removeMember(familyId: familyId, memberUid: uid);
  }

  @override
  Future<ClientProfile?> fetchFreshFamilyProfile(String familyId) async {
    final doc = await _db.collection('clients').doc(familyId).get();
    if (!doc.exists) return null;
    return ClientProfile.fromFirestore(doc);
  }

  @override
  Future<bool> hasSeenMemberTutorial(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data()?['clientTutorialSeen'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> markMemberTutorialSeen(String uid, {bool seen = true}) async {
    await _db.collection('users').doc(uid).set({
      'clientTutorialSeen': seen,
    }, SetOptions(merge: true));
  }
}
