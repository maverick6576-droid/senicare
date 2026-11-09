import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/core/core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Stream<String?> get onAuthStateChanged => _auth.authStateChanges().map((user) => user?.uid);

  @override
  Future<void> signInAnonymously() async {
    await _auth.signInAnonymously();
  }

  @override
  Future<void> signInWithCustomToken(String token) async {
    await _auth.signInWithCustomToken(token);
  }

  @override
  Future<void> signUpWithEmail(String email, String password, String role, [Map<String, dynamic>? extraData]) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final user = credential.user;
      if (user != null) {
        // Enviar correo de verificación de forma silenciosa
        try {
          await user.sendEmailVerification();
        } catch (_) {}

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': email,
          'role': role,
        });

        if (role == 'caregiver') {
          final profile = CaregiverProfile(
            id: user.uid,
            name: extraData?['name'] ?? 'Sin nombre',
            title: (extraData?['specialties'] as List?)?.join(', ') ?? 'Cuidador',
            bio: 'Nuevo cuidador registrado en espera de validación.',
            pricePerHour: (extraData?['pricePerHour'] ?? 15).toDouble(),
            rating: 0.0,
            reviewsCount: 0,
            distance: 'A calcular',
            imageUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&q=80&w=200',
            specialties: List<String>.from(extraData?['specialties'] ?? []),
            verified: false,
            verificationStatus: 'pending',
            availableSlots: {},
            dniUrl: extraData?['dniUrl'] ?? '',
            criminalRecordUrl: extraData?['criminalRecordUrl'] ?? '',
          );
          await FirebaseFirestore.instance.collection('caregivers').doc(user.uid).set(profile.toFirestore());
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error en signUpWithEmail: $e');
      rethrow;
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      debugPrint('⚠️ Error en signInWithEmail: $e');
      rethrow;
    }
  }

  @override
  Future<void> signInWithGoogle(String role, {bool isLogin = true}) async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;
      // In 7.x we must use authenticate()
      final GoogleSignInAccount? googleUser = await googleSignIn.authenticate();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      // In v7.x, accessToken is separate and requires authorizeScopes. For Firebase Auth, idToken is enough.
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _createUserDocIfNotExists(userCredential.user, role, isLogin: isLogin);
    } catch (e) {
      debugPrint('⚠️ Error en signInWithGoogle: $e');
      rethrow;
    }
  }

  @override
  Future<void> signInWithApple(String role, {bool isLogin = true}) async {
    try {
      final rawNonce = _generateNonce();
      final nonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final OAuthCredential credential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _createUserDocIfNotExists(userCredential.user, role, isLogin: isLogin);
    } catch (e) {
      debugPrint('⚠️ Error en signInWithApple: $e');
      rethrow;
    }
  }

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  Future<void> _createUserDocIfNotExists(User? user, String role, {bool isLogin = true}) async {
    if (user == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await docRef.get();
    
    if (!doc.exists) {
      await docRef.set({
        'email': user.email ?? '',
        'role': role,
      });

      if (role == 'caregiver') {
        final profile = CaregiverProfile(
          id: user.uid,
          name: user.displayName ?? 'Sin nombre',
          title: 'Cuidador',
          bio: 'Nuevo cuidador registrado en espera de validación.',
          pricePerHour: 15.0,
          rating: 0.0,
          reviewsCount: 0,
          distance: 'A calcular',
          imageUrl: user.photoURL ?? 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&q=80&w=200',
          specialties: [],
          verified: false,
          verificationStatus: 'pending',
          availableSlots: {},
          dniUrl: '',
          criminalRecordUrl: '',
        );
        await FirebaseFirestore.instance.collection('caregivers').doc(user.uid).set(profile.toFirestore());
      }
    } else {
      // If user is explicitly registering with a new role via OAuth, overwrite the role
      if (!isLogin) {
        await docRef.set({'role': role}, SetOptions(merge: true));
        
        if (role == 'caregiver') {
          final cgDoc = await FirebaseFirestore.instance.collection('caregivers').doc(user.uid).get();
          if (!cgDoc.exists) {
            final profile = CaregiverProfile(
              id: user.uid,
              name: user.displayName ?? 'Sin nombre',
              title: 'Cuidador',
              bio: 'Nuevo cuidador registrado en espera de validación.',
              pricePerHour: 15.0,
              rating: 0.0,
              reviewsCount: 0,
              distance: 'A calcular',
              imageUrl: user.photoURL ?? 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&q=80&w=200',
              specialties: [],
              verified: false,
              verificationStatus: 'pending',
              availableSlots: {},
              dniUrl: '',
              criminalRecordUrl: '',
            );
            await FirebaseFirestore.instance.collection('caregivers').doc(user.uid).set(profile.toFirestore());
          }
        }
      }
    }
  }


  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('⚠️ Error en signOut: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await user.delete();
      } catch (e) {
        debugPrint('⚠️ Error al borrar cuenta: $e');
        // Lanzamos el error por si es necessary re-auth
        rethrow;
      }
    }
  }

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  @override
  Future<String?> getUserRole(String uid) async {
    try {
      final user = _auth.currentUser;
      if (user != null && user.uid == uid && user.email != null) {
        if (user.email == 'maverick6576@gmail.com') return 'admin';
        
        final adminDoc = await FirebaseFirestore.instance.collection('admins').doc(user.email).get();
        if (adminDoc.exists) return 'admin';
      }

      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data()?['role'] as String?;
      }
    } catch (e) {
      debugPrint('⚠️ Error en getUserRole: $e');
    }
    return null;
  }

  @override
  Future<void> updateFCMToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint('⚠️ Error en sendPasswordResetEmail: $e');
      rethrow;
    }
  }
}
