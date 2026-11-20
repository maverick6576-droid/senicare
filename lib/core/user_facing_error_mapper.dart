import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Traduce errores técnicos (Firebase Auth, Firestore, Cloud Functions, Red, Stripe)
/// a mensajes empáticos, claros y seguros en español para familias, mayores y cuidadores.
/// Nunca expone trazas internas, IDs de Stripe (`pi_...`) ni nombres de reglas de seguridad.
class UserFacingErrorMapper {
  static final RegExp _sensitiveInternalPattern = RegExp(
    r'(pi_[A-Za-z0-9_]+|cs_(test|live)_[A-Za-z0-9_]+|acct_[A-Za-z0-9_]+|FirebaseException|FirebaseAuthException|PERMISSION_DENIED|regla de seguridad|StackTrace|https?://)',
    caseSensitive: false,
  );

  static String toSpanishMessage(
    Object error, {
    String fallback = 'No pudimos completar la operación en este momento. Por favor, inténtalo de nuevo.',
  }) {
    debugPrint('UserFacingErrorMapper caught: $error');

    if (error is TimeoutException) {
      return 'La conexión está tardando más de lo habitual. Comprueba tu cobertura e inténtalo de nuevo.';
    }

    if (error is FirebaseAuthException) {
      return _mapAuthError(error);
    }

    if (error is FirebaseFunctionsException) {
      return _mapFunctionsError(error, fallback: fallback);
    }

    if (error is FirebaseException) {
      return _mapFirebaseError(error, fallback: fallback);
    }

    final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (raw.isEmpty) return fallback;

    final lower = raw.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('network') ||
        lower.contains('failed host lookup') ||
        lower.contains('xmlhttprequest error')) {
      return 'Parece que no hay conexión a Internet. Revisa tu red e inténtalo de nuevo.';
    }
    if (lower.contains('cancel') && !lower.contains('no se puede cancelar')) {
      return 'La operación fue cancelada.';
    }
    if (lower.contains('permission-denied') || lower.contains('permission_denied')) {
      return 'No tienes permisos para realizar esta acción o tu sesión ha caducado.';
    }

    if (!_sensitiveInternalPattern.hasMatch(raw) && raw.length <= 180) {
      return raw;
    }

    return fallback;
  }

  static String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'user-disabled':
        return 'Esta cuenta ha sido desactivada temporalmente. Contacta con soporte si necesitas ayuda.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'El correo o la contraseña no son correctos. Revisa los datos e inténtalo de nuevo.';
      case 'email-already-in-use':
        return 'Este correo ya está registrado en SeniCare. Prueba a iniciar sesión.';
      case 'weak-password':
        return 'La contraseña es demasiado sencilla. Usa al menos 8 caracteres combinando letras y números.';
      case 'too-many-requests':
        return 'Hemos detectado demasiados intentos seguidos. Espera unos minutos antes de volver a intentarlo.';
      case 'network-request-failed':
        return 'No pudimos conectar con el servidor. Comprueba tu conexión a Internet.';
      case 'requires-recent-login':
        return 'Por tu seguridad, cierra sesión y vuelve a entrar antes de realizar este cambio.';
      case 'account-exists-with-different-credential':
        return 'Ya existe una cuenta con este correo vinculada a otro método de acceso.';
      default:
        return 'No pudimos verificar tu acceso. Por favor, revisa tus datos e inténtalo de nuevo.';
    }
  }

  static String _mapFunctionsError(
    FirebaseFunctionsException e, {
    required String fallback,
  }) {
    final msg = (e.message ?? '').trim();
    if (msg.isNotEmpty &&
        !_sensitiveInternalPattern.hasMatch(msg) &&
        msg.toLowerCase() != 'internal' &&
        msg.length <= 200) {
      return msg;
    }

    switch (e.code) {
      case 'unauthenticated':
        return 'Tu sesión ha expirado. Vuelve a iniciar sesión para continuar.';
      case 'permission-denied':
        return 'No tienes autorización para realizar esta operación.';
      case 'failed-precondition':
        return 'No se cumplen los requisitos previos para completar esta acción. Actualiza la pantalla e inténtalo de nuevo.';
      case 'resource-exhausted':
        return 'Has realizado demasiadas solicitudes seguidas. Espera unos segundos e inténtalo de nuevo.';
      case 'deadline-exceeded':
      case 'unavailable':
        return 'El servicio está tardando en responder. Por favor, inténtalo de nuevo en unos instantes.';
      case 'not-found':
        return 'No encontramos la información solicitada. Puede que haya sido actualizada recientemente.';
      default:
        return fallback;
    }
  }

  static String _mapFirebaseError(
    FirebaseException e, {
    required String fallback,
  }) {
    switch (e.code) {
      case 'permission-denied':
        return 'No tienes permisos para acceder o modificar esta información.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Sin conexión estable con el servidor. Comprueba tu Internet e inténtalo de nuevo.';
      case 'not-found':
        return 'El elemento solicitado ya no está disponible.';
      case 'canceled':
        return 'La operación fue cancelada.';
      default:
        return fallback;
    }
  }
}
