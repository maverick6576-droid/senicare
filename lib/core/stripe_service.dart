import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

class StripeService {
  static Future<void> init([String? publishableKey]) async {
    String? envKey;
    if (dotenv.isInitialized) {
      envKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'];
    }
    
    String keyToUse = 'pk_test_51ToJ11Fur4CnDyhiSd1twyovzS5N3XIPxziiJe8M16sX8YtCdbG8Dg3MVb52jhWqRjxEafM0z38twnzMePfSXB9S00xv5ahJqC';
    
    if (publishableKey != null && publishableKey.isNotEmpty) {
      keyToUse = publishableKey;
    } else if (envKey != null && envKey.isNotEmpty) {
      keyToUse = envKey;
    }

    Stripe.publishableKey = keyToUse;
    await Stripe.instance.applySettings();
  }

  /// Creates a PaymentIntent by calling the Firebase Cloud Function.
  /// Returns the intent data map or throws an exception with a readable message.
  
  static Future<Map<String, dynamic>?> createSecureBooking({
    required String caregiverId,
    String? offerId,
    String? applicationId,
    required double totalHours,
    required String day,
    required String slot,
    double? clientLatitude,
    double? clientLongitude,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: "europe-west1").httpsCallable(
        "createSecureBooking",
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final response = await callable.call({
        "caregiverId": caregiverId,
        "offerId": offerId,
        "applicationId": applicationId,
        "totalHours": totalHours,
        "day": day,
        "slot": slot,
        "clientLatitude": clientLatitude,
        "clientLongitude": clientLongitude,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      debugPrint("Error creating secure booking: $e");
      return null;
    }
  }

  static Future<Map<String, dynamic>?> createPaymentIntentOnly({
    required int amountInCents,
    required String currency,
    String? caregiverStripeAccountId,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable(
        'createPaymentIntent',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final response = await callable.call({
        'amountInCents': amountInCents,
        'currency': currency,
        'caregiverStripeAccountId': caregiverStripeAccountId,
      });
      final responseData = response.data as Map<dynamic, dynamic>?;
      if (responseData == null || responseData['clientSecret'] == null) {
        throw Exception('La Cloud Function no devolvió un clientSecret válido.');
      }
      return Map<String, dynamic>.from(responseData);
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'Cloud Function error [${e.code}]: ${e.message} | Details: ${e.details}');
      throw Exception('Error del servidor de pagos (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('Error creando PaymentIntent: $e');
      rethrow;
    }
  }

  /// Initializes the Stripe Payment Sheet.
  /// Returns true on success, false on failure.
  static Future<bool> initPaymentSheet(Map<String, dynamic> paymentIntentData) async {
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntentData['clientSecret'] as String,
          merchantDisplayName: 'SeniCare',
          style: ThemeMode.light,
          applePay: const PaymentSheetApplePay(
            merchantCountryCode: 'ES',
          ),
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'ES',
            currencyCode: 'EUR',
            testEnv: false,
          ),
        ),
      );
      return true;
    } on StripeException catch (e) {
      final msg = e.error.localizedMessage ?? e.error.message ?? 'Error desconocido de Stripe';
      debugPrint('Stripe error initializing payment sheet: $msg');
      throw Exception('StripeInitError: $msg');
    } catch (e) {
      debugPrint('Error initializing payment sheet: $e');
      throw Exception('FlutterInitError: $e');
    }
  }

  /// Presents the Stripe Payment Sheet to the user.
  /// Returns 'success', 'cancelled', or 'error'.
  static Future<String> presentPaymentSheet() async {
    try {
      await Stripe.instance.presentPaymentSheet();
      return 'success';
    } on StripeException catch (e) {
      // Check for cancellation using the localizedMessage or code string
      final code = e.error.code;
      final message = e.error.localizedMessage ?? e.error.message ?? '';
      debugPrint('Stripe presentPaymentSheet exception: code=$code, message=$message');

      // FailureCode.Canceled may differ by version — check both enum and string
      if (code == FailureCode.Canceled ||
          message.toLowerCase().contains('cancel') ||
          message.toLowerCase().contains('dismissed')) {
        return 'cancelled';
      }
      return 'error';
    } catch (e) {
      debugPrint('Unexpected error presenting payment sheet: $e');
      return 'error';
    }
  }

  static Future<String?> createConnectAccount() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('createConnectAccount');
      final response = await callable.call();
      return response.data['accountId'] as String?;
    } catch (e) {
      debugPrint('Error creando Connect Account: $e');
      rethrow;
    }
  }

  static Future<void> launchOnboarding(String accountId, {String mode = 'onboarding'}) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('getStripeAccountLink');
      final response = await callable.call({
        'accountId': accountId,
        'mode': mode,
      });
      final url = response.data['url'] as String;

      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        throw Exception('No se pudo abrir la URL: $url');
      }
    } catch (e) {
      debugPrint('Error lanzando onboarding de Stripe: $e');
      rethrow;
    }
  }

  static Future<void> openBankAccountManagement(String accountId) async {
    await launchOnboarding(accountId, mode: 'dashboard');
  }

  static Future<bool> releaseEscrowPayment({
    required String bookingId,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('releaseEscrowPayment');
      await callable.call({'bookingId': bookingId});
      return true;
    } catch (e) {
      debugPrint('Error liberando pago en Stripe: $e');
      return false;
    }
  }
}
