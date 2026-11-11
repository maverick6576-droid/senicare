import 'dart:math';

import 'package:senicare/core/dependency_injection.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/interfaces/client_repository.dart';
import 'package:senicare/repositories/interfaces/family_repository.dart';
import 'package:senicare/repositories/mock/mock_client_repository.dart';

class MockFamilyRepository implements FamilyRepository {
  MockFamilyRepository({ClientRepository Function()? clientRepositoryProvider})
      : _clientRepoProvider =
            clientRepositoryProvider ?? (() => DependencyInjection.clients);

  final ClientRepository Function() _clientRepoProvider;

  final Map<String, String> _activeFamilyByUid = {};
  final Map<String, FamilyInvite> _invitesByCode = {};
  final Map<String, bool> _memberTutorialSeen = {};
  final Random _random = Random();

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  ClientRepository get _clients => _clientRepoProvider();

  Iterable<ClientProfile> _knownClients() {
    final repo = _clients;
    if (repo is MockClientRepository) {
      return repo.allClients;
    }
    return const [];
  }

  /// Permite en tests consultar rápidamente el `activeFamilyId` guardado en `users/{uid}`.
  String? getStoredActiveFamilyId(String uid) => _activeFamilyByUid[uid];

  /// Permite en tests sembrar una invitación con código predecible.
  void seedInvite(FamilyInvite invite) {
    _invitesByCode[invite.code.toUpperCase()] = invite;
  }

  String _generateCode() {
    return List.generate(
      8,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
  }

  @override
  Future<String?> resolveActiveFamilyId({
    required String uid,
    String? email,
    String? displayName,
    bool emailVerified = false,
  }) async {
    // 1. Verificar activeFamilyId persistido si el usuario sigue siendo miembro
    final storedFamilyId = _activeFamilyByUid[uid];
    if (storedFamilyId != null && storedFamilyId.isNotEmpty) {
      final family = await _clients.getClient(storedFamilyId);
      if (family != null && family.isMember(uid)) {
        return storedFamilyId;
      }
      _activeFamilyByUid.remove(uid);
    }

    // 2. Cuenta propia ya completada (`clients/{uid}` con onboardingComplete == true)
    final ownClient = await _clients.getClient(uid);
    if (ownClient != null && ownClient.onboardingComplete) {
      _activeFamilyByUid[uid] = uid;
      return uid;
    }

    // 3. Auto-detección por email invitado (antes de crear nueva familia en onboarding)
    final normalizedEmail = email?.trim().toLowerCase() ?? '';
    if (normalizedEmail.isNotEmpty && emailVerified) {
      for (final family in _knownClients()) {
        if (family.id == uid) continue;
        final hasMatch = family.authorizedFamilyEmails
            .any((e) => e.trim().toLowerCase() == normalizedEmail);
        if (hasMatch) {
          final role = family.emailRoleFor(normalizedEmail);
          await _attachMemberToFamily(
            family: family,
            uid: uid,
            email: normalizedEmail,
            displayName: displayName ?? '',
            role: role,
            joinedVia: 'email',
            consumeInvitedEmail: normalizedEmail,
          );
          _activeFamilyByUid[uid] = family.id;
          return family.id;
        }
      }
    }

    // 4. Si existe stub sin completar (onboardingComplete == false), sigue en uid para onboarding
    if (ownClient != null) {
      return uid;
    }

    return null;
  }

  Future<ClientProfile> _attachMemberToFamily({
    required ClientProfile family,
    required String uid,
    required String email,
    required String displayName,
    required FamilyRole role,
    required String joinedVia,
    String? consumeInvitedEmail,
  }) async {
    final ownerUid = family.effectiveOwnerUid;
    final nextMembers = <String, dynamic>{};
    family.members.forEach((k, v) => nextMembers[k] = v.toMap());
    if (!nextMembers.containsKey(ownerUid)) {
      nextMembers[ownerUid] = FamilyMember(
        uid: ownerUid,
        email: '',
        displayName: family.name.isNotEmpty ? family.name : 'Administrador',
        role: FamilyRole.admin,
        joinedVia: 'owner',
        isOwner: true,
      ).toMap();
    }

    final existingMember = family.members[uid];
    nextMembers[uid] = FamilyMember(
      uid: uid,
      email: email.isNotEmpty ? email : (existingMember?.email ?? ''),
      displayName: displayName.trim().isNotEmpty
          ? displayName.trim()
          : (existingMember?.displayName ?? ''),
      role: uid == ownerUid ? FamilyRole.admin : role,
      joinedAt: existingMember?.joinedAt ?? DateTime.now(),
      joinedVia: existingMember?.joinedVia ?? joinedVia,
      isOwner: uid == ownerUid,
    ).toMap();

    final nextUids = <String>{
      ownerUid,
      ...family.memberUids,
      uid,
    }.toList();

    final nextEmails = List<String>.from(family.authorizedFamilyEmails);
    final nextEmailRoles = <String, dynamic>{};
    family.familyEmailRoles
        .forEach((k, v) => nextEmailRoles[k] = v.firestoreValue);

    if (consumeInvitedEmail != null && consumeInvitedEmail.isNotEmpty) {
      nextEmails.removeWhere(
          (e) => e.trim().toLowerCase() == consumeInvitedEmail.toLowerCase());
      nextEmailRoles.remove(consumeInvitedEmail.toLowerCase());
    }

    await _clients.updateClient(family.id, {
      'ownerUid': ownerUid,
      'memberUids': nextUids,
      'members': nextMembers,
      'authorizedFamilyEmails': nextEmails,
      'familyEmailRoles': nextEmailRoles,
    });

    return (await _clients.getClient(family.id)) ?? family;
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
    var code = _generateCode();
    while (_invitesByCode.containsKey(code)) {
      code = _generateCode();
    }
    final now = DateTime.now();
    final family = await _clients.getClient(familyId);
    final invite = FamilyInvite(
      code: code,
      familyId: familyId,
      familyName: familyName.isNotEmpty
          ? familyName
          : (family?.name.isNotEmpty == true ? family!.name : 'Familia SeniCare'),
      role: role,
      invitedEmail: invitedEmail?.trim().toLowerCase(),
      createdByUid: family?.effectiveOwnerUid ?? familyId,
      createdAt: now,
      expiresAt: now.add(validFor),
      maxUses: maxUses,
    );
    _invitesByCode[code] = invite;
    return invite;
  }

  @override
  Future<List<FamilyInvite>> getActiveInvites(String familyId) async {
    return _invitesByCode.values
        .where((i) => i.familyId == familyId && i.isActive)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> revokeInvite({
    required String familyId,
    required String code,
  }) async {
    final upper = code.trim().toUpperCase();
    final existing = _invitesByCode[upper];
    if (existing != null && existing.familyId == familyId) {
      _invitesByCode[upper] = FamilyInvite(
        code: existing.code,
        familyId: existing.familyId,
        familyName: existing.familyName,
        role: existing.role,
        invitedEmail: existing.invitedEmail,
        createdByUid: existing.createdByUid,
        createdAt: existing.createdAt,
        expiresAt: existing.expiresAt,
        maxUses: existing.maxUses,
        usedCount: existing.usedCount,
        revoked: true,
      );
    }
  }

  @override
  Future<void> inviteByEmail({
    required String familyId,
    required String email,
    required FamilyRole role,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final family = await _clients.getClient(familyId);
    final currentEmails =
        List<String>.from(family?.authorizedFamilyEmails ?? const []);
    if (!currentEmails.any((e) => e.toLowerCase() == normalized)) {
      currentEmails.add(normalized);
    }
    final nextRoles = <String, dynamic>{};
    family?.familyEmailRoles
        .forEach((k, v) => nextRoles[k] = v.firestoreValue);
    nextRoles[normalized] = role.firestoreValue;

    await _clients.updateClient(familyId, {
      'authorizedFamilyEmails': currentEmails,
      'familyEmailRoles': nextRoles,
    });
  }

  @override
  Future<void> removeEmailInvite({
    required String familyId,
    required String email,
  }) async {
    final normalized = email.trim().toLowerCase();
    final family = await _clients.getClient(familyId);
    if (family == null) return;
    final nextEmails = family.authorizedFamilyEmails
        .where((e) => e.trim().toLowerCase() != normalized)
        .toList();
    final nextRoles = <String, dynamic>{};
    family.familyEmailRoles.forEach((k, v) {
      if (k.toLowerCase() != normalized) {
        nextRoles[k] = v.firestoreValue;
      }
    });
    await _clients.updateClient(familyId, {
      'authorizedFamilyEmails': nextEmails,
      'familyEmailRoles': nextRoles,
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
    final invite = _invitesByCode[code];
    if (invite == null || invite.revoked) {
      throw StateError('Código de invitación no encontrado o revocado.');
    }
    if (invite.isExpired) {
      throw StateError('Esta invitación ha caducado. Pide un código nuevo.');
    }
    if (invite.isExhausted) {
      throw StateError('Esta invitación ha alcanzado el límite de usos.');
    }

    final family = await _clients.getClient(invite.familyId);
    if (family == null) {
      throw StateError('La cuenta familiar asociada ya no está disponible.');
    }

    final alreadyMember = family.isMember(uid);
    if (!alreadyMember) {
      await _attachMemberToFamily(
        family: family,
        uid: uid,
        email: email?.trim().toLowerCase() ?? '',
        displayName: displayName ?? '',
        role: invite.role,
        joinedVia: 'code',
      );
      _invitesByCode[code] = FamilyInvite(
        code: invite.code,
        familyId: invite.familyId,
        familyName: invite.familyName,
        role: invite.role,
        invitedEmail: invite.invitedEmail,
        createdByUid: invite.createdByUid,
        createdAt: invite.createdAt,
        expiresAt: invite.expiresAt,
        maxUses: invite.maxUses,
        usedCount: invite.usedCount + 1,
        revoked: invite.revoked,
      );
    }

    _activeFamilyByUid[uid] = family.id;
    return FamilyJoinResult(
      familyId: family.id,
      familyName: family.name.isNotEmpty ? family.name : invite.familyName,
      role: alreadyMember
          ? (family.roleFor(uid) ?? invite.role)
          : invite.role,
      joinedVia: 'code',
      alreadyMember: alreadyMember,
    );
  }

  @override
  Future<void> updateMemberRole({
    required String familyId,
    required String memberUid,
    required FamilyRole newRole,
  }) async {
    final family = await _clients.getClient(familyId);
    if (family == null) return;
    if (memberUid == family.effectiveOwnerUid &&
        newRole != FamilyRole.admin) {
      throw StateError(
          'El creador principal de la familia debe mantenerse como Administrador.');
    }
    final nextMembers = <String, dynamic>{};
    family.members.forEach((k, v) => nextMembers[k] = v.toMap());
    final target = family.members[memberUid];
    if (target == null) return;
    nextMembers[memberUid] = target.copyWith(role: newRole).toMap();
    await _clients.updateClient(familyId, {'members': nextMembers});
  }

  @override
  Future<void> removeMember({
    required String familyId,
    required String memberUid,
  }) async {
    final family = await _clients.getClient(familyId);
    if (family == null) return;
    if (memberUid == family.effectiveOwnerUid) {
      throw StateError('No se puede eliminar al propietario de la cuenta familiar.');
    }
    final nextMembers = <String, dynamic>{};
    family.members.forEach((k, v) {
      if (k != memberUid) nextMembers[k] = v.toMap();
    });
    final nextUids =
        family.memberUids.where((u) => u != memberUid).toList();
    if (!nextUids.contains(family.effectiveOwnerUid)) {
      nextUids.insert(0, family.effectiveOwnerUid);
    }
    if (_activeFamilyByUid[memberUid] == familyId) {
      _activeFamilyByUid.remove(memberUid);
    }
    await _clients.updateClient(familyId, {
      'memberUids': nextUids,
      'members': nextMembers,
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
  Future<ClientProfile?> fetchFreshFamilyProfile(String familyId) {
    return _clients.getClient(familyId);
  }

  @override
  Future<bool> hasSeenMemberTutorial(String uid) async {
    return _memberTutorialSeen[uid] ?? false;
  }

  @override
  Future<void> markMemberTutorialSeen(String uid, {bool seen = true}) async {
    _memberTutorialSeen[uid] = seen;
  }
}
