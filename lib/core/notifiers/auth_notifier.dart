import 'dart:async';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/repositories/repositories.dart';

class AuthNotifier extends ChangeNotifier {
  bool isAuthenticated = false;
  String? currentUserId;
  String currentRole = 'client';
  bool onboardingComplete = false;
  bool isAdminVerified2FA = false;
  
  ClientProfile? currentClient;
  String? activeFamilyId;
  String? _sessionEmailOverride;
  String? _sessionNameOverride;
  bool? _sessionVerifiedOverride;

  String? get currentUserEmail {
    if (_sessionEmailOverride != null) return _sessionEmailOverride;
    final repo = DependencyInjection.auth;
    if (repo is FirebaseAuthRepository) return repo.currentUserEmail;
    if (repo is MockAuthRepository) return repo.currentUserEmail;
    return null;
  }

  String? get currentUserDisplayName {
    if (_sessionNameOverride != null) return _sessionNameOverride;
    final repo = DependencyInjection.auth;
    if (repo is FirebaseAuthRepository) return repo.currentUserDisplayName;
    if (repo is MockAuthRepository) return repo.currentUserDisplayName;
    return null;
  }

  bool get isCurrentUserEmailVerified {
    if (_sessionVerifiedOverride != null) return _sessionVerifiedOverride!;
    final repo = DependencyInjection.auth;
    if (repo is FirebaseAuthRepository) return repo.isCurrentUserEmailVerified;
    if (repo is MockAuthRepository) return repo.currentUserEmailVerified;
    return false;
  }

  void configureFamilySessionOverrides({
    String? email,
    String? displayName,
    bool? emailVerified,
  }) {
    _sessionEmailOverride = email;
    _sessionNameOverride = displayName;
    _sessionVerifiedOverride = emailVerified;
  }

  /// ID efectivo de la cuenta familiar cuando está en modo cliente.
  String? get effectiveClientId {
    if (currentRole == 'client') {
      return activeFamilyId ?? currentClient?.id ?? currentUserId;
    }
    return currentUserId;
  }

  /// Rol del usuario actual dentro de la cuenta familiar compartida.
  FamilyRole? get currentFamilyRole {
    if (currentRole != 'client') return null;
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return null;
    final client = currentClient;
    if (client == null || uid == client.id || uid == client.effectiveOwnerUid) {
      return client?.roleFor(uid) ?? FamilyRole.admin;
    }
    return client.roleFor(uid) ?? FamilyRole.collaborator;
  }

  bool get isSharedFamilyMember {
    if (currentRole != 'client') return false;
    final uid = currentUserId;
    final client = currentClient;
    if (uid == null || client == null) return false;
    return client.id != uid && client.effectiveOwnerUid != uid;
  }

  bool get isClientFamilyAdmin =>
      currentRole == 'client' &&
      (currentFamilyRole?.canManagePayments ?? true);

  bool get canManageFamilyPayments => isClientFamilyAdmin;
  bool get canManageFamilyMembers => isClientFamilyAdmin;
  bool get canManageCareDetails =>
      currentRole == 'client' &&
      (currentFamilyRole?.canManageCareDetails ?? true);

  String get currentActorLabel {
    final uid = currentUserId;
    final client = currentClient;
    if (uid != null && client != null && client.members.containsKey(uid)) {
      return client.members[uid]!.effectiveName;
    }
    final name = currentUserDisplayName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = currentUserEmail?.trim() ?? '';
    if (email.contains('@')) return email.split('@').first;
    return currentClient?.name ?? 'Familiar';
  }

  Future<void> refreshFamilyProfile() async {
    if (currentRole != 'client') return;
    final targetId = effectiveClientId;
    if (targetId == null || targetId.isEmpty) return;
    final fresh =
        await DependencyInjection.families.fetchFreshFamilyProfile(targetId) ??
            await DependencyInjection.clients.getClient(targetId);
    if (fresh != null) {
      activeFamilyId = fresh.id;
      currentClient = fresh;
      onboardingComplete = fresh.onboardingComplete;
      notifyListeners();
    }
  }

  Future<FamilyJoinResult> joinFamilyWithCode(String codeOrUrl) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('Debes iniciar sesión para unirte a una familia.');
    }
    final result = await DependencyInjection.families.joinWithCode(
      uid: uid,
      codeOrUrl: codeOrUrl,
      email: currentUserEmail,
      displayName: currentUserDisplayName,
    );
    activeFamilyId = result.familyId;
    await refreshFamilyProfile();
    return result;
  }

  Future<void> leaveSharedFamily() async {
    final uid = currentUserId;
    final famId = effectiveClientId;
    if (uid == null || famId == null || !isSharedFamilyMember) return;
    await DependencyInjection.families.leaveFamily(
      familyId: famId,
      uid: uid,
    );
    activeFamilyId = null;
    currentClient = null;
    await reloadRole();
  }
  CaregiverProfile? currentCaregiver;

  StreamSubscription? _authSubscription;

  AuthNotifier() {
    _initAuthListener();
  }

  void forceRefresh() => notifyListeners();

  void _initAuthListener() {
    _authSubscription = DependencyInjection.auth.onAuthStateChanged.listen((userId) async {
      if (userId != null) {
        isAuthenticated = true;
        currentUserId = userId;
        
        await reloadRole();

        // Actualizar FCM Token para el usuario actual
        final fcmToken = await FCMService.getToken();
        if (fcmToken != null) {
          await DependencyInjection.auth.updateFCMToken(fcmToken);
        }
      } else {
        _clearState();
      }
    });
  }

  Future<void> reloadRole() async {
    final uid = currentUserId;
    if (uid == null) return;

    // 1. Verificar primero si existe un perfil de cuidador en la base de datos
    final caregiver = await DependencyInjection.caregivers.getCaregiver(uid);
    final hasCaregiverProfile = caregiver != null;
    
    if (hasCaregiverProfile) {
      currentRole = 'caregiver';
      currentCaregiver = caregiver;
      onboardingComplete = caregiver.onboardingComplete;
    } else {
      // Retry loop to handle DB write latency (race condition during signup)
      String? role;
      int retries = 0;
      while (role == null && retries < 12) {
        if (currentUserId != uid) return; // Auth state changed during reload
        role = await DependencyInjection.auth.getUserRole(uid);
        if (role == null) {
          await Future.delayed(const Duration(milliseconds: 500));
          retries++;
        }
      }

      if (role != null) {
        currentRole = role;
      }

      // Check onboarding status
      if (currentRole == 'client') {
        final resolvedFamilyId =
            await DependencyInjection.families.resolveActiveFamilyId(
          uid: uid,
          email: currentUserEmail,
          displayName: currentUserDisplayName,
          emailVerified: isCurrentUserEmailVerified,
        );
        activeFamilyId = resolvedFamilyId;
        final targetClientId = resolvedFamilyId ?? uid;
        currentClient = await DependencyInjection.families
                .fetchFreshFamilyProfile(targetClientId) ??
            await DependencyInjection.clients.getClient(targetClientId);
        onboardingComplete = currentClient?.onboardingComplete ?? false;
      } else if (currentRole == 'caregiver') {
        try {
          currentCaregiver = await DependencyInjection.caregivers.getCaregiver(uid);
          onboardingComplete = currentCaregiver?.onboardingComplete ?? false;
        } catch (e) {
          onboardingComplete = false;
          currentCaregiver = null;
        }
      } else if (currentRole == 'admin') {
        // Admin might not have a profile, skip
        isAdminVerified2FA = false; // Requiere verificación por defecto
      }
    }

    notifyListeners();
  }

  void setRole(String role) {
    currentRole = role;
    notifyListeners();
  }

  void _clearState() {
    isAuthenticated = false;
    currentUserId = null;
    currentRole = 'client';
    onboardingComplete = false;
    activeFamilyId = null;
    currentClient = null;
    currentCaregiver = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
