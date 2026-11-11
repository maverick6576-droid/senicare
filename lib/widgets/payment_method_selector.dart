import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:senicare/core/core.dart';

class _PaymentOptionSpec {
  final ClientPaymentMethod method;
  final IconData icon;
  final Color accentColor;
  final String? badgeText;

  const _PaymentOptionSpec({
    required this.method,
    required this.icon,
    required this.accentColor,
    this.badgeText,
  });
}

/// Tarjeta reutilizable y accesible para elegir método de pago (Apple Pay,
/// Google Pay, Tarjeta/Link, Bizum, Klarna, Revolut Pay y Adeudo SEPA).
class PaymentMethodSelectorCard extends StatelessWidget {
  final ClientPaymentMethod selectedMethod;
  final ValueChanged<ClientPaymentMethod> onChanged;
  final bool seniorMode;
  final bool platformPaySupported;

  const PaymentMethodSelectorCard({
    super.key,
    required this.selectedMethod,
    required this.onChanged,
    this.seniorMode = false,
    this.platformPaySupported = false,
  });

  static List<_PaymentOptionSpec> _buildOptions(TargetPlatform platform) {
    final isApple = platform == TargetPlatform.iOS;
    return [
      _PaymentOptionSpec(
        method: ClientPaymentMethod.platformPay,
        icon: isApple ? Icons.apple_rounded : Icons.account_balance_wallet_rounded,
        accentColor: Colors.black87,
        badgeText: '1 toque',
      ),
      const _PaymentOptionSpec(
        method: ClientPaymentMethod.bizum,
        icon: Icons.phonelink_ring_rounded,
        accentColor: Color(0xFF05C3DD),
        badgeText: 'Instantáneo ES',
      ),
      const _PaymentOptionSpec(
        method: ClientPaymentMethod.cardAndLink,
        icon: Icons.credit_card_rounded,
        accentColor: AppTheme.primary,
        badgeText: 'Guardar tarjeta',
      ),
      const _PaymentOptionSpec(
        method: ClientPaymentMethod.klarna,
        icon: Icons.calendar_view_week_rounded,
        accentColor: Color(0xFFFFB3C7),
        badgeText: '3 cuotas 0%',
      ),
      const _PaymentOptionSpec(
        method: ClientPaymentMethod.revolutPay,
        icon: Icons.bolt_rounded,
        accentColor: Color(0xFF191C1F),
      ),
      const _PaymentOptionSpec(
        method: ClientPaymentMethod.sepaDebit,
        icon: Icons.account_balance_rounded,
        accentColor: Color(0xFF1D4ED8),
        badgeText: 'IBAN directo',
      ),
      const _PaymentOptionSpec(
        method: ClientPaymentMethod.allSheet,
        icon: Icons.tune_rounded,
        accentColor: AppTheme.secondaryColor,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final options = _buildOptions(platform);

    return Container(
      padding: EdgeInsets.all(seniorMode ? 16 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_rounded, color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Método de pago',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: seniorMode ? 17.5 : 15.5,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Elige cómo pagar de forma segura. El dinero se protege en custodia hasta completar el servicio.',
            style: TextStyle(
              fontSize: seniorMode ? 13.5 : 12,
              color: AppTheme.slateMuted,
            ),
          ),
          const SizedBox(height: 12),
          ...options.map((opt) {
            final isSelected = selectedMethod == opt.method;
            final label = opt.method.labelForPlatform(platform);
            final subtitle = opt.method.subtitleForPlatform(platform);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                key: ValueKey('payment_method_${opt.method.name}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(opt.method);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: EdgeInsets.symmetric(
                    horizontal: seniorMode ? 14 : 12,
                    vertical: seniorMode ? 12 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primarySurface.withValues(alpha: 0.75)
                        : AppTheme.backgroundNeutral,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.borderSubtle,
                      width: isSelected ? 1.8 : 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: seniorMode ? 40 : 36,
                        height: seniorMode ? 40 : 36,
                        decoration: BoxDecoration(
                          color: opt.accentColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          opt.icon,
                          color: opt.method == ClientPaymentMethod.klarna
                              ? const Color(0xFF9D174D)
                              : opt.accentColor,
                          size: seniorMode ? 22 : 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: seniorMode ? 15 : 13.5,
                                    color: AppTheme.darkSlate,
                                  ),
                                ),
                                if (opt.badgeText != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppTheme.primary
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppTheme.primary
                                            : AppTheme.borderSubtle,
                                      ),
                                    ),
                                    child: Text(
                                      opt.badgeText!,
                                      style: TextStyle(
                                        fontSize: seniorMode ? 11 : 10,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? Colors.white
                                            : AppTheme.slateMuted,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: seniorMode ? 12.5 : 11.5,
                                color: AppTheme.slateMuted,
                                height: 1.25,
                              ),
                            ),
                            if (opt.method == ClientPaymentMethod.platformPay &&
                                platformPaySupported &&
                                isSelected) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Cartera digital verificada en este dispositivo ✓',
                                style: TextStyle(
                                  fontSize: seniorMode ? 12 : 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.secondaryColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: isSelected ? AppTheme.primary : AppTheme.slateMuted,
                        size: seniorMode ? 24 : 21,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Barra inferior / botón de pago que muestra el botón nativo oficial de Apple Pay
/// o Google Pay cuando está disponible y seleccionado, o el botón estándar accesible.
class PrimaryCheckoutActionBar extends StatelessWidget {
  final ClientPaymentMethod selectedMethod;
  final bool platformPaySupported;
  final bool isProcessing;
  final bool seniorMode;
  final String fallbackButtonLabel;
  final VoidCallback onPressed;

  const PrimaryCheckoutActionBar({
    super.key,
    required this.selectedMethod,
    required this.platformPaySupported,
    required this.isProcessing,
    required this.fallbackButtonLabel,
    required this.onPressed,
    this.seniorMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final showNativePlatformPay = !isProcessing &&
        platformPaySupported &&
        selectedMethod == ClientPaymentMethod.platformPay &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    if (showNativePlatformPay) {
      return SizedBox(
        height: seniorMode ? 56 : 50,
        width: double.infinity,
        child: PlatformPayButton(
          onPressed: onPressed,
          type: PlatformButtonType.pay,
          appearance: PlatformButtonStyle.black,
          borderRadius: 14,
        ),
      );
    }

    return SizedBox(
      height: seniorMode ? 56 : 50,
      width: double.infinity,
      child: FilledButton(
        onPressed: isProcessing ? null : onPressed,
        child: isProcessing
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _iconForMethod(selectedMethod, Theme.of(context).platform),
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      fallbackButtonLabel,
                      style: TextStyle(
                        fontSize: seniorMode ? 16.5 : 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static IconData _iconForMethod(ClientPaymentMethod method, TargetPlatform platform) {
    switch (method) {
      case ClientPaymentMethod.platformPay:
        return platform == TargetPlatform.iOS
            ? Icons.apple_rounded
            : Icons.account_balance_wallet_rounded;
      case ClientPaymentMethod.bizum:
        return Icons.phonelink_ring_rounded;
      case ClientPaymentMethod.klarna:
        return Icons.calendar_view_week_rounded;
      case ClientPaymentMethod.revolutPay:
        return Icons.bolt_rounded;
      case ClientPaymentMethod.sepaDebit:
        return Icons.account_balance_rounded;
      case ClientPaymentMethod.cardAndLink:
      case ClientPaymentMethod.allSheet:
        return Icons.lock_rounded;
    }
  }
}

/// Resultado unificado del flujo de cobro seleccionado por el cliente.
class CheckoutFlowResult {
  final String outcome; // 'success' | 'processing' | 'cancelled' | 'error'
  final String? paymentIntentId;
  final String? paymentMethodType;

  const CheckoutFlowResult({
    required this.outcome,
    this.paymentIntentId,
    this.paymentMethodType,
  });
}

/// Ejecuta la confirmación en Stripe según el método elegido (Wallet nativo 1-toque,
/// Checkout externo Bizum con verificación al regresar, o PaymentSheet completo).
Future<CheckoutFlowResult> executeClientStripePayment({
  required BuildContext context,
  required ClientPaymentMethod method,
  required bool platformPaySupported,
  required Map<String, dynamic> paymentIntentData,
  required double totalEur,
  required String itemLabel,
  String? customerEmail,
  String? customerName,
  String? caregiverStripeAccountId,
  String? familyId,
  List<String> bookingIds = const [],
}) async {
  final transferGroup = paymentIntentData['transferGroup']?.toString();
  final piId = paymentIntentData['paymentIntentId']?.toString();

  // 1. Pago externo vía Stripe Checkout (ej. Bizum con confirmación en app del banco)
  if (method.usesExternalCheckout) {
    final session = await StripeService.createAlternativeCheckoutSession(
      amountInCents: (totalEur * 100).round(),
      currency: 'eur',
      preferredMethod: method.backendId,
      title: itemLabel,
      caregiverStripeAccountId: caregiverStripeAccountId,
      familyId: familyId,
      transferGroup: transferGroup,
      bookingIds: bookingIds,
    );
    final url = session['url']?.toString() ?? '';
    final sessionId = session['sessionId']?.toString() ?? '';
    final launched = await StripeService.launchCheckoutUrl(url);
    if (!launched || !context.mounted) {
      return CheckoutFlowResult(
        outcome: 'error',
        paymentIntentId: piId,
        paymentMethodType: method.backendId,
      );
    }

    return showExternalPaymentVerificationDialog(
      context: context,
      sessionId: sessionId,
      methodName: method.labelForPlatform(Theme.of(context).platform),
      fallbackPaymentIntentId: piId,
    );
  }

  // 2. Apple Pay / Google Pay directo (PlatformPay 1-toque) cuando el dispositivo lo soporta
  if (method == ClientPaymentMethod.platformPay && platformPaySupported) {
    final clientSecret = paymentIntentData['clientSecret']?.toString() ?? '';
    final platformOutcome = await StripeService.payWithPlatformPay(
      clientSecret: clientSecret,
      amountEur: totalEur,
      itemLabel: itemLabel,
      customerEmail: customerEmail,
    );
    if (platformOutcome == 'success' || platformOutcome == 'cancelled') {
      final platformMethod = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
          ? 'apple_pay'
          : 'google_pay';
      return CheckoutFlowResult(
        outcome: platformOutcome,
        paymentIntentId: piId,
        paymentMethodType: platformMethod,
      );
    }
    // Si falla el wallet nativo por configuración temporal, cae con gracia a PaymentSheet
  }

  // 3. Stripe PaymentSheet (Tarjeta, Link, Apple Pay, Google Pay, Klarna, Revolut Pay, SEPA)
  final sheetOk = await StripeService.initPaymentSheet(
    paymentIntentData,
    customerEmail: customerEmail,
    customerName: customerName,
    preferredMethod: method,
  );
  if (!sheetOk) {
    return CheckoutFlowResult(
      outcome: 'error',
      paymentIntentId: piId,
      paymentMethodType: method.backendId,
    );
  }

  final outcome = await StripeService.presentPaymentSheet();
  if (outcome == 'success' && method.isDelayedBankMethod) {
    return CheckoutFlowResult(
      outcome: 'processing',
      paymentIntentId: piId,
      paymentMethodType: method.backendId,
    );
  }
  return CheckoutFlowResult(
    outcome: outcome,
    paymentIntentId: piId,
    paymentMethodType: method.backendId,
  );
}

/// Diálogo reactivo que escucha la vuelta del navegador/app bancaria (Bizum)
/// y verifica en Stripe si el cobro se completó.
Future<CheckoutFlowResult> showExternalPaymentVerificationDialog({
  required BuildContext context,
  required String sessionId,
  required String methodName,
  String? fallbackPaymentIntentId,
}) async {
  final result = await showDialog<CheckoutFlowResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExternalCheckoutVerificationDialog(
      sessionId: sessionId,
      methodName: methodName,
      fallbackPaymentIntentId: fallbackPaymentIntentId,
    ),
  );
  return result ??
      CheckoutFlowResult(
        outcome: 'cancelled',
        paymentIntentId: fallbackPaymentIntentId,
        paymentMethodType: 'bizum',
      );
}

class _ExternalCheckoutVerificationDialog extends StatefulWidget {
  final String sessionId;
  final String methodName;
  final String? fallbackPaymentIntentId;

  const _ExternalCheckoutVerificationDialog({
    required this.sessionId,
    required this.methodName,
    this.fallbackPaymentIntentId,
  });

  @override
  State<_ExternalCheckoutVerificationDialog> createState() =>
      _ExternalCheckoutVerificationDialogState();
}

class _ExternalCheckoutVerificationDialogState
    extends State<_ExternalCheckoutVerificationDialog> with WidgetsBindingObserver {
  bool _checking = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyNow(autoTriggered: true);
    }
  }

  Future<void> _verifyNow({bool autoTriggered = false}) async {
    if (_checking || !mounted) return;
    setState(() {
      _checking = true;
      _statusMessage = 'Comprobando confirmación con tu banco...';
    });

    try {
      final res = await StripeService.verifyStripePaymentStatus(
        sessionId: widget.sessionId,
      );
      final isPaid = res['isPaid'] == true;
      final isProcessing = res['isProcessing'] == true;
      final resolvedPi = res['paymentIntentId']?.toString() ??
          widget.fallbackPaymentIntentId;
      final methodType = res['paymentMethodType']?.toString() ?? 'bizum';

      if (isPaid && mounted) {
        Navigator.of(context).pop(
          CheckoutFlowResult(
            outcome: 'success',
            paymentIntentId: resolvedPi,
            paymentMethodType: methodType,
          ),
        );
        return;
      }
      if (isProcessing && mounted) {
        Navigator.of(context).pop(
          CheckoutFlowResult(
            outcome: 'processing',
            paymentIntentId: resolvedPi,
            paymentMethodType: methodType,
          ),
        );
        return;
      }
      if (mounted) {
        setState(() {
          _checking = false;
          _statusMessage = autoTriggered
              ? 'Aún no hemos recibido la confirmación bancaria. Si ya aceptaste el pago en tu app, pulsa "Verificar pago".'
              : 'El banco todavía no confirma la operación. Complétala primero o cancela para elegir otro método.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _statusMessage = 'No se pudo verificar todavía. Vuelve a intentarlo en unos segundos.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        'Completa tu pago con ${widget.methodName}',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aprueba la operación en la ventana segura o en la app de tu banco. Al volver a SeniCare verificaremos el cobro al instante.',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: AppTheme.slateMuted),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primarySurface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  if (_checking)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.darkSlate),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking
              ? null
              : () => Navigator.of(context).pop(
                    CheckoutFlowResult(
                      outcome: 'cancelled',
                      paymentIntentId: widget.fallbackPaymentIntentId,
                      paymentMethodType: 'bizum',
                    ),
                  ),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _checking ? null : () => _verifyNow(),
          child: Text(_checking ? 'Verificando...' : 'Ya he pagado · Verificar'),
        ),
      ],
    );
  }
}
