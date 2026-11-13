import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:senicare/core/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Métodos de pago disponibles para clientes de SeniCare en España (EUR).
enum ClientPaymentMethod {
  /// Pago rápido nativo con Apple Pay (iOS) o Google Pay (Android).
  platformPay,

  /// Tarjeta de crédito/débito y Stripe Link con guardado para la familia.
  cardAndLink,

  /// Bizum: pago móvil instantáneo aprobado en la app bancaria del cliente.
  bizum,

  /// Klarna: pago en 3 plazos sin intereses o diferido a 30 días.
  klarna,

  /// Revolut Pay: aprobación instantánea en 1 toque con Revolut.
  revolutPay,

  /// Adeudo directo SEPA (IBAN): domiciliación bancaria segura en EUR.
  sepaDebit,

  /// Pasarela completa Stripe PaymentSheet con todas las opciones disponibles.
  allSheet,
}

extension ClientPaymentMethodX on ClientPaymentMethod {
  String get backendId {
    switch (this) {
      case ClientPaymentMethod.platformPay:
        return 'wallet';
      case ClientPaymentMethod.cardAndLink:
        return 'card_link';
      case ClientPaymentMethod.bizum:
        return 'bizum';
      case ClientPaymentMethod.klarna:
        return 'klarna';
      case ClientPaymentMethod.revolutPay:
        return 'revolut_pay';
      case ClientPaymentMethod.sepaDebit:
        return 'sepa_debit';
      case ClientPaymentMethod.allSheet:
        return 'auto';
    }
  }

  /// Orden sugerido dentro de Stripe PaymentSheet para resaltar la opción elegida.
  List<String> get paymentMethodOrder {
    switch (this) {
      case ClientPaymentMethod.platformPay:
        return const ['card', 'link', 'klarna', 'revolut_pay', 'sepa_debit'];
      case ClientPaymentMethod.cardAndLink:
        return const ['card', 'link', 'klarna', 'revolut_pay', 'sepa_debit'];
      case ClientPaymentMethod.bizum:
        return const ['bizum', 'card', 'link'];
      case ClientPaymentMethod.klarna:
        return const ['klarna', 'card', 'link'];
      case ClientPaymentMethod.revolutPay:
        return const ['revolut_pay', 'card', 'link'];
      case ClientPaymentMethod.sepaDebit:
        return const ['sepa_debit', 'card', 'link'];
      case ClientPaymentMethod.allSheet:
        return const ['card', 'link', 'klarna', 'revolut_pay', 'sepa_debit'];
    }
  }

  bool get usesExternalCheckout => this == ClientPaymentMethod.bizum || kIsWeb;

  bool get isDelayedBankMethod => this == ClientPaymentMethod.sepaDebit;

  String labelForPlatform(TargetPlatform platform) {
    switch (this) {
      case ClientPaymentMethod.platformPay:
        if (platform == TargetPlatform.iOS) return 'Apple Pay';
        if (platform == TargetPlatform.android) return 'Google Pay';
        return 'Apple Pay / Google Pay';
      case ClientPaymentMethod.cardAndLink:
        return 'Tarjeta o Link';
      case ClientPaymentMethod.bizum:
        return 'Bizum';
      case ClientPaymentMethod.klarna:
        return 'Klarna (3 cuotas sin intereses)';
      case ClientPaymentMethod.revolutPay:
        return 'Revolut Pay';
      case ClientPaymentMethod.sepaDebit:
        return 'Transferencia / Adeudo SEPA';
      case ClientPaymentMethod.allSheet:
        return 'Todos los métodos disponibles';
    }
  }

  String subtitleForPlatform(TargetPlatform platform) {
    switch (this) {
      case ClientPaymentMethod.platformPay:
        if (platform == TargetPlatform.iOS) {
          return '1 toque con Face ID / Touch ID y tarjetas de Apple Wallet';
        }
        if (platform == TargetPlatform.android) {
          return '1 toque con huella o PIN y tarjetas de Google Wallet';
        }
        return 'Pago exprés en 1 toque con la cartera de tu dispositivo';
      case ClientPaymentMethod.cardAndLink:
        return 'Visa, Mastercard, American Express y autocompletado seguro Link';
      case ClientPaymentMethod.bizum:
        return 'Introduce tu móvil y confirma el pago en la app de tu banco';
      case ClientPaymentMethod.klarna:
        return 'Divide el total en 3 pagos sin intereses o paga en 30 días';
      case ClientPaymentMethod.revolutPay:
        return 'Pago instantáneo desde tu cuenta Revolut con 1 confirmación';
      case ClientPaymentMethod.sepaDebit:
        return 'Domiciliación directa con tu IBAN europeo sin usar tarjeta';
      case ClientPaymentMethod.allSheet:
        return 'Tarjeta, Wallets, Link, Klarna, Revolut Pay y SEPA en una sola pantalla';
    }
  }
}

class StripeService {
  static const String _defaultTestPublishableKey =
      'pk_test_51ToJ11Fur4CnDyhiSd1twyovzS5N3XIPxziiJe8M16sX8YtCdbG8Dg3MVb52jhWqRjxEafM0z38twnzMePfSXB9S00xv5ahJqC';
  static const String defaultMerchantIdentifier = 'merchant.com.senicare.app';
  static const String returnUrl = 'senicare://stripe-redirect';

  static String _configuredPublishableKey = _defaultTestPublishableKey;
  static String _configuredMerchantId = defaultMerchantIdentifier;

  static bool get isTestMode => _configuredPublishableKey.startsWith('pk_test_');
  static String get merchantIdentifier => _configuredMerchantId;

  static Future<void> init([String? publishableKey, String? merchantId]) async {
    String? envKey;
    String? envMerchant;
    if (dotenv.isInitialized) {
      envKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'];
      envMerchant = dotenv.env['STRIPE_MERCHANT_IDENTIFIER'];
    }

    String keyToUse = _defaultTestPublishableKey;
    if (publishableKey != null && publishableKey.isNotEmpty) {
      keyToUse = publishableKey;
    } else if (envKey != null && envKey.isNotEmpty) {
      keyToUse = envKey;
    }

    String merchantToUse = defaultMerchantIdentifier;
    if (merchantId != null && merchantId.isNotEmpty) {
      merchantToUse = merchantId;
    } else if (envMerchant != null && envMerchant.isNotEmpty) {
      merchantToUse = envMerchant;
    }

    _configuredPublishableKey = keyToUse;
    _configuredMerchantId = merchantToUse;

    Stripe.publishableKey = keyToUse;
    Stripe.merchantIdentifier = merchantToUse;
    Stripe.urlScheme = 'senicare';
    Stripe.setReturnUrlSchemeOnAndroid = true;
    await Stripe.instance.applySettings();
  }

  /// Comprueba de forma segura si Apple Pay (iOS) o Google Pay (Android) nativo está operativo.
  static Future<bool> isPlatformPaySupported() async {
    if (kIsWeb) return false;
    final isMobile = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    if (!isMobile) return false;

    try {
      return await Stripe.instance.isPlatformPaySupported(
        googlePay: IsGooglePaySupportedParams(
          testEnv: isTestMode,
          existingPaymentMethodRequired: false,
        ),
      );
    } catch (e) {
      debugPrint('isPlatformPaySupported check unavailable: $e');
      return false;
    }
  }

  /// Crea reservas de pago atómicamente en servidor (precios, descuentos, PIN y Stripe Intent/Session).
  static Future<Map<String, dynamic>> createSecureBooking({
    required String caregiverId,
    String? offerId,
    String? applicationId,
    String? familyId,
    String preferredMethod = 'auto',
    bool useCheckoutSession = false,
    List<Map<String, dynamic>>? sessions,
    double? totalHours,
    String? day,
    String? slot,
    double? clientLatitude,
    double? clientLongitude,
    List<String> checklist = const [],
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
        'createSecureBooking',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final normalizedSessions = sessions ??
          [
            if (day != null && slot != null)
              {
                'day': day,
                'slot': slot,
                'totalHours': ?totalHours,
              }
          ];
      final response = await callable.call({
        'caregiverId': caregiverId,
        if (offerId != null && offerId.isNotEmpty) 'offerId': offerId,
        if (applicationId != null && applicationId.isNotEmpty)
          'applicationId': applicationId,
        if (familyId != null && familyId.isNotEmpty) 'familyId': familyId,
        'preferredMethod': preferredMethod,
        'useCheckoutSession': useCheckoutSession,
        'sessions': normalizedSessions,
        'clientLatitude': ?clientLatitude,
        'clientLongitude': ?clientLongitude,
        if (checklist.isNotEmpty) 'checklist': checklist,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'createSecureBooking error [${e.code}]: ${e.message} | Details: ${e.details}',
      );
      throw Exception(e.message ?? 'Error al crear la reserva segura (${e.code}).');
    } catch (e) {
      debugPrint('Error creating secure booking: $e');
      rethrow;
    }
  }

  /// Verifica Check-in del cuidador en servidor mediante QR + GPS o PIN secreto.
  static Future<Map<String, dynamic>> verifyBookingCheckIn({
    required String bookingId,
    required String method,
    String? pin,
    String? qrValue,
    double? latitude,
    double? longitude,
    double? accuracy,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
        'verifyBookingCheckIn',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      final response = await callable.call({
        'bookingId': bookingId,
        'method': method,
        'pin': ?pin,
        'qrValue': ?qrValue,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'accuracy': ?accuracy,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'No se pudo verificar el check-in (${e.code}).');
    }
  }

  /// Libera franjas y borra borradores `pendingPayment` de forma atómica si el pago se cancela.
  static Future<void> cancelPendingCheckout(List<String> bookingIds) async {
    if (bookingIds.isEmpty) return;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('cancelPendingCheckout');
      await callable.call({'bookingIds': bookingIds});
    } catch (e) {
      debugPrint('cancelPendingCheckout warning: $e');
    }
  }

  static Future<Map<String, dynamic>?> createPaymentIntentOnly({
    required int amountInCents,
    required String currency,
    String? caregiverStripeAccountId,
    String preferredMethod = 'auto',
    String? familyId,
    String? description,
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
        'preferredMethod': preferredMethod,
        if (familyId != null && familyId.isNotEmpty) 'familyId': familyId,
        if (description != null && description.isNotEmpty)
          'description': description,
      });
      final responseData = response.data as Map<dynamic, dynamic>?;
      if (responseData == null || responseData['clientSecret'] == null) {
        throw Exception('La Cloud Function no devolvió un clientSecret válido.');
      }
      return Map<String, dynamic>.from(responseData);
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'Cloud Function error [${e.code}]: ${e.message} | Details: ${e.details}',
      );
      throw Exception('Error del servidor de pagos (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('Error creando PaymentIntent: $e');
      rethrow;
    }
  }

  /// Crea una sesión de Stripe Checkout optimizada para métodos con app externa (p. ej. Bizum).
  static Future<Map<String, dynamic>> createAlternativeCheckoutSession({
    required int amountInCents,
    required String currency,
    required String preferredMethod,
    required String title,
    String? caregiverStripeAccountId,
    String? familyId,
    String? transferGroup,
    List<String> bookingIds = const [],
  }) async {
    try {
      final callable =
          FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable(
        'createAlternativeCheckoutSession',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final response = await callable.call({
        'amountInCents': amountInCents,
        'currency': currency,
        'preferredMethod': preferredMethod,
        'title': title,
        'caregiverStripeAccountId': caregiverStripeAccountId,
        if (familyId != null && familyId.isNotEmpty) 'familyId': familyId,
        if (transferGroup != null && transferGroup.isNotEmpty)
          'transferGroup': transferGroup,
        'bookingIds': bookingIds,
      });
      final map = Map<String, dynamic>.from(response.data as Map);
      if (map['url'] == null || map['sessionId'] == null) {
        throw Exception('La sesión de pago alternativa no devolvió una URL válida.');
      }
      return map;
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Error preparando pago (${e.code}): ${e.message}');
    }
  }

  /// Abre la pasarela web segura de Stripe (Bizum / app bancaria / Checkout Web).
  static Future<bool> launchCheckoutUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  /// Verifica en tiempo real el estado del cobro en Stripe tras regresar de Bizum/redirección.
  static Future<Map<String, dynamic>> verifyStripePaymentStatus({
    String? sessionId,
    String? paymentIntentId,
  }) async {
    final callable =
        FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable(
      'verifyStripePaymentStatus',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    final response = await callable.call({
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
      if (paymentIntentId != null && paymentIntentId.isNotEmpty)
        'paymentIntentId': paymentIntentId,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Ejecuta el flujo nativo de 1 toque de Apple Pay (iOS) o Google Pay (Android).
  static Future<String> payWithPlatformPay({
    required String clientSecret,
    required double amountEur,
    required String itemLabel,
    String? customerEmail,
  }) async {
    try {
      final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      final confirmParams = isIos
          ? PlatformPayConfirmParams.applePay(
              applePay: ApplePayParams(
                merchantCountryCode: 'ES',
                currencyCode: 'EUR',
                cartItems: [
                  ApplePayCartSummaryItem.immediate(
                    label: itemLabel,
                    amount: amountEur.toStringAsFixed(2),
                  ),
                ],
              ),
            )
          : PlatformPayConfirmParams.googlePay(
              googlePay: GooglePayParams(
                testEnv: isTestMode,
                merchantCountryCode: 'ES',
                currencyCode: 'EUR',
                merchantName: 'SeniCare',
                allowCreditCards: true,
              ),
            );

      await Stripe.instance.confirmPlatformPayPaymentIntent(
        clientSecret: clientSecret,
        confirmParams: confirmParams,
      );
      return 'success';
    } on StripeException catch (e) {
      final code = e.error.code;
      final message = e.error.localizedMessage ?? e.error.message ?? '';
      debugPrint('PlatformPay StripeException: code=$code, message=$message');
      if (code == FailureCode.Canceled ||
          message.toLowerCase().contains('cancel') ||
          message.toLowerCase().contains('dismissed')) {
        return 'cancelled';
      }
      return 'error';
    } catch (e) {
      debugPrint('Unexpected PlatformPay error: $e');
      return 'error';
    }
  }

  /// Initializes the Stripe Payment Sheet con soporte completo para Apple Pay,
  /// Google Pay, Tarjeta, Link, Klarna, Revolut Pay, Adeudo SEPA y tarjetas guardadas.
  static Future<bool> initPaymentSheet(
    Map<String, dynamic> paymentIntentData, {
    String? customerEmail,
    String? customerName,
    ClientPaymentMethod preferredMethod = ClientPaymentMethod.allSheet,
  }) async {
    try {
      final customerId = paymentIntentData['customerId']?.toString();
      final customerSessionSecret =
          paymentIntentData['customerSessionClientSecret']?.toString();
      final ephemeralKeySecret =
          paymentIntentData['ephemeralKeySecret']?.toString();

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret:
              paymentIntentData['clientSecret'] as String,
          merchantDisplayName: 'SeniCare',
          style: ThemeMode.light,
          customerId: customerId != null && customerId.isNotEmpty
              ? customerId
              : null,
          customerSessionClientSecret:
              customerSessionSecret != null && customerSessionSecret.isNotEmpty
                  ? customerSessionSecret
                  : null,
          customerEphemeralKeySecret: (customerSessionSecret == null ||
                      customerSessionSecret.isEmpty) &&
                  ephemeralKeySecret != null &&
                  ephemeralKeySecret.isNotEmpty
              ? ephemeralKeySecret
              : null,
          allowsDelayedPaymentMethods: true,
          returnURL: returnUrl,
          paymentMethodOrder: preferredMethod.paymentMethodOrder,
          billingDetails: BillingDetails(
            email: customerEmail != null && customerEmail.isNotEmpty
                ? customerEmail
                : null,
            name: customerName != null && customerName.isNotEmpty
                ? customerName
                : null,
            address: const Address(
              city: null,
              country: 'ES',
              line1: null,
              line2: null,
              postalCode: null,
              state: null,
            ),
          ),
          applePay: const PaymentSheetApplePay(
            merchantCountryCode: 'ES',
          ),
          googlePay: PaymentSheetGooglePay(
            merchantCountryCode: 'ES',
            currencyCode: 'EUR',
            testEnv: isTestMode,
          ),
          appearance: PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: AppTheme.primary,
              background: Colors.white,
              componentBackground: AppTheme.backgroundNeutral,
              primaryText: AppTheme.darkSlate,
              secondaryText: AppTheme.slateMuted,
            ),
            shapes: const PaymentSheetShape(
              borderRadius: 14,
              borderWidth: 1,
            ),
          ),
        ),
      );
      return true;
    } on StripeException catch (e) {
      final msg =
          e.error.localizedMessage ?? e.error.message ?? 'Error desconocido de Stripe';
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
      final code = e.error.code;
      final message = e.error.localizedMessage ?? e.error.message ?? '';
      debugPrint(
        'Stripe presentPaymentSheet exception: code=$code, message=$message',
      );

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

  static Future<void> launchOnboarding(
    String accountId, {
    String mode = 'onboarding',
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('getStripeAccountLink');
      final response = await callable.call({
        'accountId': accountId,
        'mode': mode,
      });
      final url = response.data['url'] as String;

      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
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

  /// Synchronizes the connected Stripe account KYC status with Firestore.
  static Future<bool> syncStripeKycStatus() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('syncStripeKycStatus');
      final response = await callable.call();
      return response.data['isVerified'] == true;
    } catch (e) {
      debugPrint('Error sincronizando estado KYC de Stripe: $e');
      rethrow;
    }
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

  static Future<Map<String, dynamic>> confirmClientBookingPayment({
    required List<String> bookingIds,
    String? paymentIntentId,
    String? sessionId,
    String targetStatus = 'pending',
    String? transferGroup,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('confirmClientBookingPayment');
    final response = await callable.call({
      'bookingIds': bookingIds,
      if (paymentIntentId != null && paymentIntentId.isNotEmpty)
        'paymentIntentId': paymentIntentId,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
      'targetStatus': targetStatus,
      if (transferGroup != null && transferGroup.isNotEmpty)
        'transferGroup': transferGroup,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> createTipPaymentIntent({
    required String bookingId,
    required double tipAmount,
    String preferredMethod = 'auto',
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('createTipPaymentIntent');
    final response = await callable.call({
      'bookingId': bookingId,
      'tipAmount': tipAmount,
      'preferredMethod': preferredMethod,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> confirmTipPayment({
    required String bookingId,
    required String paymentIntentId,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('confirmTipPayment');
    final response = await callable.call({
      'bookingId': bookingId,
      'paymentIntentId': paymentIntentId,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Cobra la propina en Stripe mediante PaymentSheet y liquida el registro
  /// en Firestore/Transfer Connect a través de `confirmTipPayment`.
  static Future<bool> payTipWithStripe({
    required String bookingId,
    required double tipAmount,
    String? customerEmail,
    String? customerName,
  }) async {
    await init();
    final intentData = await createTipPaymentIntent(
      bookingId: bookingId,
      tipAmount: tipAmount,
    );
    final clientSecret = intentData['clientSecret']?.toString() ?? '';
    final paymentIntentId = intentData['paymentIntentId']?.toString() ?? '';
    if (clientSecret.isEmpty || paymentIntentId.isEmpty) {
      throw Exception('No se pudo preparar el pago de la propina.');
    }

    await initPaymentSheet(
      intentData,
      customerEmail: customerEmail,
      customerName: customerName,
    );

    final outcome = await presentPaymentSheet();
    if (outcome == 'cancelled') {
      return false;
    }
    if (outcome != 'success') {
      throw Exception('No se pudo completar el cobro de la propina en Stripe.');
    }

    await confirmTipPayment(
      bookingId: bookingId,
      paymentIntentId: paymentIntentId,
    );
    return true;
  }

  static Future<void> setupAdmin2FA({
    required String secret,
    required String code,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('setupAdmin2FA');
    await callable.call({
      'secret': secret,
      'code': code,
    });
  }

  static Future<void> verifyAdmin2FA({required String code}) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('verifyAdmin2FA');
    await callable.call({'code': code});
  }

  static Future<Map<String, dynamic>> syncUserClaims() async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('syncUserClaims');
    final response = await callable.call();
    return Map<String, dynamic>.from(response.data as Map);
  }
}
