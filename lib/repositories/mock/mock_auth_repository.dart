import 'dart:async';
import 'package:flutter/material.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/core/core.dart';

class MockAuthRepository implements AuthRepository {
  final _controller = StreamController<String?>.broadcast();
  String? _currentUser;
  String? _currentUserRole = 'client';
  String? adminOverrideEmail;

  MockAuthRepository() {
    // Removed automatic anonymous login so the user sees the AuthScreen.
  }

  @override
  Stream<String?> get onAuthStateChanged => _controller.stream;

  @override
  Future<void> signInAnonymously() async {
    _currentUser = 'mock_client_123';
    _currentUserRole = 'client';
    _controller.add(_currentUser);
  }

  @override
  Future<void> signInWithCustomToken(String token) async {
    _currentUser = token;
    _controller.add(_currentUser);
  }

  @override
  Future<void> signUpWithEmail(String email, String password, String role, [Map<String, dynamic>? extraData]) async {
    _currentUser = 'mock_user_${DateTime.now().millisecondsSinceEpoch}';
    _currentUserRole = (adminOverrideEmail == email) ? 'admin' : role;
    
    if (_currentUserRole == 'caregiver') {
      await DependencyInjection.caregivers.updateProfile(_currentUser!, {
        'name': 'Sin nombre',
        'onboardingComplete': false,
        'verificationStatus': 'pending',
      });
    } else if (_currentUserRole == 'client') {
      await DependencyInjection.clients.updateClient(_currentUser!, {
        'name': 'Sin nombre',
        'onboardingComplete': false,
      });
    }
    
    _controller.add(_currentUser);
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    _currentUser = 'mock_user_123';
    _currentUserRole = (adminOverrideEmail == email) ? 'admin' : 'client';
    _controller.add(_currentUser);
  }

  @override
  Future<void> signInWithGoogle(String role, {bool isLogin = true}) async {
    _currentUser = 'mock_user_123';
    if (!isLogin) {
      _currentUserRole = role;
      if (role == 'caregiver') {
        await DependencyInjection.caregivers.updateProfile(_currentUser!, {
          'name': 'Sin nombre',
          'onboardingComplete': false,
          'verificationStatus': 'pending',
        });
      } else if (role == 'client') {
        await DependencyInjection.clients.updateClient(_currentUser!, {
          'name': 'Sin nombre',
          'onboardingComplete': false,
        });
      }
    } else {
      _currentUserRole ??= role;
    }
    _controller.add(_currentUser);
  }

  @override
  Future<void> signInWithApple(String role, {bool isLogin = true}) async {
    _currentUser = 'mock_user_123';
    if (!isLogin) {
      _currentUserRole = role;
      if (role == 'caregiver') {
        await DependencyInjection.caregivers.updateProfile(_currentUser!, {
          'name': 'Sin nombre',
          'onboardingComplete': false,
          'verificationStatus': 'pending',
        });
      } else if (role == 'client') {
        await DependencyInjection.clients.updateClient(_currentUser!, {
          'name': 'Sin nombre',
          'onboardingComplete': false,
        });
      }
    } else {
      _currentUserRole ??= role;
    }
    _controller.add(_currentUser);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    _currentUser = null;
    _controller.add(null);
  }

  @override
  String? get currentUserId => _currentUser;

  @override
  Future<String?> getUserRole(String uid) async {
    return _currentUserRole;
  }

  @override
  Future<void> updateFCMToken(String token) async {
    debugPrint('MockAuthRepository: FCM token updated to $token');
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    debugPrint('MockAuthRepository: Enlace de recuperación enviado a $email');
  }
}
