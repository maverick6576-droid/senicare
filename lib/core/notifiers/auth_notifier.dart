import 'dart:async';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';

class AuthNotifier extends ChangeNotifier {
  bool isAuthenticated = false;
  String? currentUserId;
  String currentRole = 'client';
  bool onboardingComplete = false;
  bool isAdminVerified2FA = false;
  
  ClientProfile? currentClient;
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
        currentClient = await DependencyInjection.clients.getClient(uid);
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
