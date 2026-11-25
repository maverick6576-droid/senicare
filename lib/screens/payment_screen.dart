import 'dart:async';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/core/core.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:math';
import 'package:senicare/widgets/widgets.dart';

class PaymentScreen extends StatefulWidget {
  final CaregiverProfile caregiver;
  final String dateString;
  final List<TimeSlot> slots;
  final DateTime? customStartTime;
  final DateTime? customEndTime;

  const PaymentScreen({
    super.key,
    required this.caregiver,
    required this.dateString,
    required this.slots,
    this.customStartTime,
    this.customEndTime,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _isLoading = true;
  bool _isProcessingPayment = false;
  bool _platformPaySupported = false;
  ClientPaymentMethod _selectedPaymentMethod = ClientPaymentMethod.platformPay;
  int _accumulatedHours = 0;
  bool _applyPackDiscount = false;
  List<String> _customChecklist = [];
  final TextEditingController _taskCtrl = TextEditingController();

  // Tracks booking IDs created in Firestore so we can delete them on rollback.
  final List<String> _createdBookingIds = [];

  bool get _hasCustomRange =>
      widget.customStartTime != null &&
      widget.customEndTime != null &&
      widget.customEndTime!.isAfter(widget.customStartTime!);

  double get _exactHours {
    if (_hasCustomRange) {
      return widget.customEndTime!
              .difference(widget.customStartTime!)
              .inMinutes /
          60.0;
    }
    return widget.slots.length.toDouble();
  }

  @override
  void initState() {
    super.initState();
    final client = context.read<AuthNotifier>().currentClient;
    _customChecklist = List<String>.from(client?.defaultCareChecklist ?? []);
    _applyPackDiscount = _exactHours >= 4.0;
    unawaited(ObservabilityService.logEvent(
      'checkout_opened',
      parameters: {
        'caregiver_id': widget.caregiver.id,
        'hours': _exactHours,
      },
    ));
    _loadStats();
    _detectPlatformPay();
  }

  Future<void> _detectPlatformPay() async {
    final supported = await StripeService.isPlatformPaySupported();
    if (mounted) {
      setState(() => _platformPaySupported = supported);
    }
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final auth = context.read<AuthNotifier>();
      final clientId = auth.effectiveClientId ?? 'unknown';
      final hours = await DependencyInjection.stats
          .getAccumulatedHours(clientId, widget.caregiver.id);
      if (mounted) {
        setState(() {
          _accumulatedHours = hours;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Safe setState: only calls setState if the widget is still mounted.
  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _showSnackBar(ScaffoldMessengerState messenger, String message, Color color) {
    messenger.showSnackBar(SnackBar(
      content: Semantics(
        liveRegion: true,
        child: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      backgroundColor: color,
      duration: const Duration(seconds: 4),
    ));
  }

  /// Rolls back any slots and bookings already created when payment fails or is
  /// cancelled. Runs best-effort: errors are logged but never shown to the user.
  Future<void> _rollback() async {
    debugPrint('Payment rollback: reverting ${widget.slots.length} slot(s) '
        'and ${_createdBookingIds.length} booking(s).');

    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await StripeService.cancelPendingCheckout(
        List<String>.from(_createdBookingIds),
      );
      _createdBookingIds.clear();
      return;
    }

    // Mock-mode rollback: re-open local slots & delete draft bookings
    for (final s in widget.slots) {
      try {
        s.isAvailable = true;
        await DependencyInjection.caregivers
            .updateTimeSlot(widget.caregiver.id, widget.dateString, s);
      } catch (e) {
        debugPrint('Rollback: failed to restore slot ${s.dateTime}: $e');
      }
    }

    for (final id in _createdBookingIds) {
      try {
        await DependencyInjection.bookings.deleteBooking(id);
      } catch (e) {
        debugPrint('Rollback: failed to delete booking $id: $e');
      }
    }

    _createdBookingIds.clear();
  }

  Future<void> _handlePayment() async {
    if (_isProcessingPayment) return;
    // ── 0. Capture all context-dependent objects BEFORE any async gap ──
    final auth = context.read<AuthNotifier>();
    final bookingState = context.read<BookingNotifier>();
    final location = context.read<LocationNotifier>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final clientId = auth.effectiveClientId ?? 'unknown';
    if (!auth.canManageFamilyPayments) {
      _showSnackBar(
        scaffoldMessenger,
        'Solo un Administrador de la familia puede confirmar pagos y reservas.',
        AppTheme.warning,
      );
      return;
    }
    final bool isPackEligible = _exactHours >= 4.0;
    _applyPackDiscount = isPackEligible;
    final double caregiverCommissionRate =
        FirestoreStatsRepository.calculateCommissionRate(_accumulatedHours);
    final double totalHours = _exactHours;
    final double baseCost =
        ((widget.caregiver.pricePerHour * totalHours) * 100).roundToDouble() /
            100.0;
    final double effectiveClientFeeRate =
        FirestoreStatsRepository.calculateEffectiveClientFeeRate(
      _accumulatedHours,
      isFourHourPack: isPackEligible,
    );
    final double clientFeeTotal =
        FirestoreStatsRepository.calculateClientFeeAmount(
      baseCost: baseCost,
      accumulatedHours: _accumulatedHours,
      isFourHourPack: isPackEligible,
    );
    double total = ((baseCost + clientFeeTotal) * 100).roundToDouble() / 100.0;
    final double? homeLat = auth.currentClient?.latitude ?? location.latitude;
    final double? homeLon = auth.currentClient?.longitude ?? location.longitude;

    _safeSetState(() => _isProcessingPayment = true);

    // ── 1. Connectivity check ──
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        _safeSetState(() => _isProcessingPayment = false);
        _showSnackBar(scaffoldMessenger,
            'Sin conexión a internet. No se puede procesar el pago.', AppTheme.danger);
        return;
      }
    } catch (e) {
      debugPrint('Connectivity check error: $e');
    }

    // ── 2. Validate Stripe account ──
    final stripeAccountId = widget.caregiver.stripeAccountId;
    if (stripeAccountId == null || stripeAccountId.isEmpty) {
      _safeSetState(() => _isProcessingPayment = false);
      _showSnackBar(
        scaffoldMessenger,
        'Este cuidador aún no ha configurado su cuenta de pago. Contacta con soporte.',
        AppTheme.warning,
      );
      return;
    }

    // ── 3. Agrupar franjas contiguas ──
    final sortedSlots = List<TimeSlot>.from(widget.slots)
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    List<List<TimeSlot>> groupedSlots = [];
    List<TimeSlot> currentGroup = [];
    for (var s in sortedSlots) {
      if (currentGroup.isEmpty) {
        currentGroup.add(s);
      } else {
        final lastSlot = currentGroup.last;
        final diff = s.dateTime.difference(lastSlot.dateTime);
        if (diff.inMinutes == 60) {
          currentGroup.add(s);
        } else {
          groupedSlots.add(currentGroup);
          currentGroup = [s];
        }
      }
    }
    if (currentGroup.isNotEmpty) {
      groupedSlots.add(currentGroup);
    }

    Map<String, dynamic> paymentIntentData = {
      'transferGroup': 'booking_${DateTime.now().millisecondsSinceEpoch}',
    };
    String generatedPin = (Random().nextInt(9000) + 1000).toString();
    String? paymentIntentId;

    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      // Flujo seguro de producción: precios, comisiones, bloqueo de franjas y PIN en Cloud Function
      try {
        final sessionsPayload = _hasCustomRange
            ? [
                {
                  'day': widget.dateString,
                  'slot':
                      '${TimeInterval.formatHm(widget.customStartTime!)}-${TimeInterval.formatHm(widget.customEndTime!)}',
                  'totalHours': _exactHours,
                }
              ]
            : groupedSlots.map((group) {
                final startSlot = group.first;
                final endSlot = group.last;
                final endDateTime =
                    endSlot.dateTime.add(const Duration(hours: 1));
                final startTimeStr =
                    '${startSlot.dateTime.hour.toString().padLeft(2, '0')}:${startSlot.dateTime.minute.toString().padLeft(2, '0')}';
                final endTimeStr =
                    '${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}';
                return {
                  'day': widget.dateString,
                  'slot': '$startTimeStr-$endTimeStr',
                  'totalHours': group.length,
                };
              }).toList();

        final created = await StripeService.createSecureBooking(
          caregiverId: widget.caregiver.id,
          familyId: clientId,
          preferredMethod: _selectedPaymentMethod.backendId,
          useCheckoutSession: _selectedPaymentMethod.usesExternalCheckout,
          sessions: sessionsPayload,
          clientLatitude: homeLat,
          clientLongitude: homeLon,
          checklist: _customChecklist,
        );
        paymentIntentData = created;
        paymentIntentId = created['paymentIntentId']?.toString();
        generatedPin = created['bookingPin']?.toString() ?? generatedPin;
        final serverTotal = (created['totalEur'] as num?)?.toDouble();
        if (serverTotal != null && serverTotal > 0) {
          total = serverTotal;
        }
        final rawIds = created['bookingIds'] as List<dynamic>? ?? [];
        _createdBookingIds
          ..clear()
          ..addAll(rawIds.map((e) => e.toString()).where((e) => e.isNotEmpty));
        if (_createdBookingIds.isEmpty) {
          throw Exception('El servidor no devolvió reservas válidas.');
        }
      } catch (e) {
        debugPrint('Error in createSecureBooking: $e');
        _safeSetState(() => _isProcessingPayment = false);
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'No se pudo iniciar la reserva',
            message: UserFacingErrorMapper.toSpanishMessage(e),
          );
        }
        return;
      }
    } else {
      // Modo Mock (pruebas y simulación local)
      try {
        final latestSlots = await DependencyInjection.caregivers
            .fetchTimeSlots(widget.caregiver.id, widget.dateString);
        for (final selected in widget.slots) {
          final match = latestSlots.where((s) =>
              s.dateTime.hour == selected.dateTime.hour &&
              s.dateTime.minute == selected.dateTime.minute).firstOrNull;
          if (match != null && !match.isAvailable) {
            _safeSetState(() => _isProcessingPayment = false);
            _showSnackBar(
              scaffoldMessenger,
              'La hora ${selected.dateTime.hour.toString().padLeft(2, '0')}:00 acaba de ser reservada por otra familia. Por favor, elige otro horario.',
              AppTheme.warning,
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('Slot verification warning: $e');
      }

      try {
        for (var s in widget.slots) {
          s.isAvailable = false;
          await DependencyInjection.caregivers
              .updateTimeSlot(widget.caregiver.id, widget.dateString, s);
        }
        for (var group in groupedSlots) {
          final startSlot = group.first;
          final endSlot = group.last;
          final endDateTime = endSlot.dateTime.add(const Duration(hours: 1));
          final startTimeStr = '${startSlot.dateTime.hour.toString().padLeft(2, '0')}:${startSlot.dateTime.minute.toString().padLeft(2, '0')}';
          final endTimeStr = '${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}';
          final slotRangeStr = '$startTimeStr-$endTimeStr';

          final groupHours = group.length;
          final groupCost = widget.caregiver.pricePerHour * groupHours;
          final groupClientFee = totalHours > 0
              ? ((clientFeeTotal * (groupHours / totalHours)) * 100)
                      .roundToDouble() /
                  100.0
              : groupCost * effectiveClientFeeRate;
          final groupTotalPaid = groupCost + groupClientFee;
          final groupCommission = groupCost * caregiverCommissionRate;
          final groupPayout = groupCost - groupCommission;

          final newBooking = Booking(
            id: '${DateTime.now().millisecondsSinceEpoch}_${startTimeStr.replaceAll(':', '')}',
            clientId: clientId,
            caregiverId: widget.caregiver.id,
            caregiverName: widget.caregiver.name,
            day: widget.dateString,
            slot: slotRangeStr,
            cost: groupCost,
            clientFee: groupClientFee,
            clientFeeRate: effectiveClientFeeRate,
            caregiverCommissionRate: caregiverCommissionRate,
            caregiverCommissionAmount: groupCommission,
            caregiverPayout: groupPayout,
            totalPaid: groupTotalPaid,
            transferGroup: paymentIntentData['transferGroup']?.toString(),
            paymentIntentId: paymentIntentId,
            paymentMethodType: _selectedPaymentMethod.backendId,
            paymentStatus: 'pending',
            clientLatitude: homeLat,
            clientLongitude: homeLon,
            bookingPin: generatedPin,
            status: BookingStatus.pendingPayment,
            escrowStatus: 'none',
            careChecklist: _customChecklist
                .asMap()
                .entries
                .map((e) => CareChecklistItem(
                      id: 'task_${e.key}_${DateTime.now().millisecondsSinceEpoch}',
                      title: e.value,
                    ))
                .toList(),
          );

          final firestoreId = await bookingState.addBooking(newBooking);
          _createdBookingIds.add(firestoreId);
        }
      } catch (e) {
        debugPrint('Error creating mock bookings: $e');
        await _rollback();
        _safeSetState(() => _isProcessingPayment = false);
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'Error al crear la reserva',
            message: 'No se pudo registrar la reserva. El pago NO ha sido procesado.\n\n${UserFacingErrorMapper.toSpanishMessage(e)}',
          );
        }
        return;
      }
    }

    final transferGroup = paymentIntentData['transferGroup']?.toString() ??
        'booking_${DateTime.now().millisecondsSinceEpoch}';

    // ── 5. Present selected Stripe payment method (Express Wallet, Bizum Checkout or PaymentSheet) ──
    if (!mounted) {
      _safeSetState(() => _isProcessingPayment = false);
      return;
    }

    CheckoutFlowResult flowResult;
    try {
      final customerName = auth.currentClient?.name ?? auth.currentUserDisplayName;
      flowResult = await executeClientStripePayment(
        context: context,
        method: _selectedPaymentMethod,
        platformPaySupported: _platformPaySupported,
        paymentIntentData: paymentIntentData,
        totalEur: total,
        itemLabel: 'Cuidado con ${widget.caregiver.name}',
        customerEmail: auth.currentUserEmail,
        customerName: customerName,
        caregiverStripeAccountId: stripeAccountId,
        familyId: clientId,
        bookingIds: List<String>.from(_createdBookingIds),
      );
    } catch (e) {
      debugPrint('Unexpected error during payment flow: $e');
      flowResult = const CheckoutFlowResult(outcome: 'error');
    } finally {
      _safeSetState(() => _isProcessingPayment = false);
    }

    // ── 6. Handle result ──
    switch (flowResult.outcome) {
      case 'success':
      case 'processing':
        unawaited(ObservabilityService.logEvent(
          'payment_succeeded',
          parameters: {
            'method': _selectedPaymentMethod.backendId,
            'outcome': flowResult.outcome,
            'total_eur': total,
          },
        ));
        if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
          try {
            await StripeService.confirmClientBookingPayment(
              bookingIds: List<String>.from(_createdBookingIds),
              paymentIntentId: flowResult.paymentIntentId ?? paymentIntentId,
              sessionId: flowResult.sessionId,
              targetStatus: 'pending',
              transferGroup: transferGroup,
            );
          } catch (e) {
            debugPrint('confirmClientBookingPayment warning (webhook reconciles): $e');
          }
        } else {
          for (final id in _createdBookingIds) {
            try {
              await DependencyInjection.bookings.updateBookingStatus(id, 'pending');
            } catch (e) {
              debugPrint('Failed to update booking status to pending: $e');
            }
          }
        }
        _createdBookingIds.clear();
        if (mounted) {
          HapticFeedback.heavyImpact();
          await _showBookingSuccessModal(
            context,
            total,
            generatedPin,
            isProcessingBank: flowResult.outcome == 'processing',
          );
        }
        navigator.popUntil((route) => route.isFirst);

      case 'cancelled':
        await _rollback();
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'Pago no completado',
            message: 'Has cerrado la pasarela de pago antes de finalizar. Tu reserva no se ha cobrado. Puedes elegir cualquier otro método (Apple Pay, Google Pay, Bizum, Klarna, Tarjeta o SEPA).',
          );
        }

      default:
        await _rollback();
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'Operación no completada',
            message: 'No se pudo autorizar el pago con el método elegido. Revisa tus datos o prueba con Apple Pay, Google Pay, Bizum o Tarjeta.',
          );
        }
    }
  }

  Future<void> _showBookingSuccessModal(
    BuildContext context,
    double totalPaid,
    String pin, {
    bool isProcessingBank = false,
  }) async {
    final dateFormatted = DateFormat('dd/MM/yyyy').format(DateTime.parse(widget.dateString));
    final hoursStr = _hasCustomRange
        ? '${TimeInterval.formatHm(widget.customStartTime!)} - ${TimeInterval.formatHm(widget.customEndTime!)}'
        : widget.slots
            .map((s) => '${s.dateTime.hour.toString().padLeft(2, '0')}:${s.dateTime.minute.toString().padLeft(2, '0')}')
            .join(', ');
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(22),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_rounded, color: AppTheme.secondaryColor, size: 48),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '¡Reserva Solicitada con Éxito!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
              ),
              const SizedBox(height: 6),
              Text(
                isProcessingBank
                    ? 'Orden SEPA autorizada por ${totalPaid.toStringAsFixed(2)} €. Tu banco la procesará en 1-3 días hábiles y quedará protegida bajo Stripe Escrow para ${widget.caregiver.name}.'
                    : 'Tu pago de ${totalPaid.toStringAsFixed(2)} € está protegido en custodia bancaria (Stripe Escrow). Solo se liberará a ${widget.caregiver.name} tras realizar el cuidado.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Text(
                      '🔑 CÓDIGO PIN DE ENTRADA AL DOMICILIO',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pin,
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 6, color: AppTheme.darkSlate),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Entrégaselo al cuidador cuando llegue a casa',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final text = '✅ Reserva en SeniCare con ${widget.caregiver.name}\n'
                        '📅 Fecha: $dateFormatted ($hoursStr)\n'
                        '🔑 Código PIN de llegada: $pin\n'
                        '🛡️ Pago protegido en garantía: ${totalPaid.toStringAsFixed(2)} €';
                    await Clipboard.setData(ClipboardData(text: text));
                    if (ctx.mounted) {
                      CustomSnackBar.show(ctx, message: '📋 Recibo y PIN copiados para enviar por WhatsApp a tu familia.', type: SnackBarType.success);
                    }
                  },
                  icon: const Icon(Icons.share_rounded, size: 17),
                  label: const Text(
                    'Compartir recibo y PIN por WhatsApp',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Finalizar e ir al Inicio',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManagementFeeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.shield_rounded, color: AppTheme.primary, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '¿Qué incluye el Escudo de Protección Familiar?',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('• 🔐 Custodia Bancaria Stripe Escrow: tu dinero queda retenido y no se transfiere hasta verificar la llegada con PIN/QR.', style: TextStyle(fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 8),
              const Text('• 🛡️ Cobertura y Verificación: identidad DNI/NIE, antecedentes y seguro de responsabilidad civil hasta 500.000€ durante el turno.', style: TextStyle(fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 8),
              const Text('• 🏆 Fidelidad Compartida: tu cuota baja automáticamente del 5% al 3,5% (+30h) y al 2% (+100h) con el mismo cuidador, y se reduce un -50% en reservas de 4h o más sin recortar el sueldo del cuidador.', style: TextStyle(fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigNotifier>();
    final theme = Theme.of(context);
    final seniorMode = config.seniorMode;
    final currencyFormat = NumberFormat.currency(symbol: '€', decimalDigits: 2);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pago Seguro')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final double totalHours = _exactHours;
    _applyPackDiscount = totalHours >= 4.0;
    final double rawBaseCost =
        ((widget.caregiver.pricePerHour * totalHours) * 100).roundToDouble() /
            100.0;
    final double baseCost = rawBaseCost;
    final double fullShieldFee =
        FirestoreStatsRepository.calculateClientFeeAmount(
      baseCost: baseCost,
      accumulatedHours: _accumulatedHours,
      isFourHourPack: false,
    );
    final double clientFee = FirestoreStatsRepository.calculateClientFeeAmount(
      baseCost: baseCost,
      accumulatedHours: _accumulatedHours,
      isFourHourPack: _applyPackDiscount,
    );
    final double packDiscountAmount =
        ((fullShieldFee - clientFee) * 100).roundToDouble() / 100.0;
    final double effectiveFeePct =
        FirestoreStatsRepository.calculateEffectiveClientFeeRate(
              _accumulatedHours,
              isFourHourPack: _applyPackDiscount,
            ) *
            100;
    final String feePctLabel = effectiveFeePct % 1 == 0
        ? effectiveFeePct.toStringAsFixed(0)
        : effectiveFeePct.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');
    final double total = baseCost + clientFee;

    return Scaffold(
      appBar: AppBar(title: const Text('Pago Seguro')),
      body: ListView(
        padding: EdgeInsets.all(seniorMode ? 24 : 16),
        children: [
          Text('Resumen de Reserva', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _applyPackDiscount
                  ? AppTheme.secondaryColor.withValues(alpha: 0.12)
                  : AppTheme.backgroundNeutral,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _applyPackDiscount
                    ? AppTheme.secondaryColor.withValues(alpha: 0.4)
                    : AppTheme.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: Text('📦', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bono Familiar Multi-Sesión (-50% en Escudo)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.darkSlate),
                      ),
                      Text(
                        totalHours >= 4.0
                            ? 'Activado: ahorras ${currencyFormat.format(packDiscountAmount)} en la cuota de protección y el cuidador recibe el 100% de su tarifa (${FirestoreStatsRepository.familyLoyaltyTierTitle(_accumulatedHours)})'
                            : 'Reserva 4h o más para reducir un 50% la cuota del Escudo Familiar (${FirestoreStatsRepository.familyLoyaltyTierTitle(_accumulatedHours)})',
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _applyPackDiscount
                        ? AppTheme.secondaryColor
                        : AppTheme.backgroundNeutral,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _applyPackDiscount
                          ? AppTheme.secondaryColor
                          : AppTheme.borderSubtle,
                    ),
                  ),
                  child: Text(
                    _applyPackDiscount ? '-50% Cuota' : '4h+ Auto',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _applyPackDiscount
                          ? Colors.white
                          : AppTheme.slateMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Cuidador:'),
                      Text(
                        widget.caregiver.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Fecha:'),
                      Text(
                        DateFormat('dd/MM/yyyy')
                            .format(DateTime.parse(widget.dateString)),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Horarios:'),
                      Text(
                        _hasCustomRange
                            ? '${TimeInterval.formatHm(widget.customStartTime!)} - ${TimeInterval.formatHm(widget.customEndTime!)}'
                            : widget.slots
                                .map((s) =>
                                    '${s.dateTime.hour.toString().padLeft(2, '0')}:${s.dateTime.minute.toString().padLeft(2, '0')}')
                                .join(', '),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Duración:'),
                      Text(
                        '${totalHours.toStringAsFixed(totalHours % 1 == 0 ? 0 : 2)} hora${totalHours > 1 ? 's' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Honorarios del cuidador:'),
                      Text(currencyFormat.format(rawBaseCost)),
                    ],
                  ),
                  if (_applyPackDiscount) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          '📦 Bono Familiar 4h+ (-50% en Escudo):',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.secondarySenior),
                        ),
                        Text(
                          '-${currencyFormat.format(packDiscountAmount)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.secondarySenior),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Semantics(
                        button: true,
                        excludeSemantics: true,
                        label: 'Escudo de Protección ($feePctLabel%). Pulsa para ver qué incluye',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _showManagementFeeSheet(context),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    '🛡️ Escudo de Protección ($feePctLabel%):',
                                    style: const TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Text(currencyFormat.format(clientFee),
                          style: const TextStyle(color: AppTheme.slateMuted)),
                    ],
                  ),
                  const Divider(height: 32),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Total:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      Text(
                        currencyFormat.format(total),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                            fontSize: 22),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          PaymentMethodSelectorCard(
            selectedMethod: _selectedPaymentMethod,
            seniorMode: seniorMode,
            platformPaySupported: _platformPaySupported,
            onChanged: (method) {
              setState(() => _selectedPaymentMethod = method);
            },
          ),
          const SizedBox(height: 20),
          _buildCheckoutCareChecklistCard(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primarySurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_user_rounded, color: AppTheme.primary, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pago 100% Protegido y Cancelación Gratuita',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppTheme.darkSlate,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• Tu dinero queda protegido en custodia (Stripe Escrow) y solo se transfiere a ${widget.caregiver.name.split(' ').first} tras realizar el cuidado en casa.\n'
                  '• Cancelación gratuita con reembolso íntegro hasta 24 horas antes del servicio.\n'
                  '• Seguro de Responsabilidad Civil y soporte familiar incluidos.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.slateMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: PrimaryCheckoutActionBar(
            selectedMethod: _selectedPaymentMethod,
            platformPaySupported: _platformPaySupported,
            isProcessing: _isProcessingPayment,
            seniorMode: seniorMode,
            fallbackButtonLabel:
                'Pagar ${currencyFormat.format(total)} · ${_selectedPaymentMethod.labelForPlatform(Theme.of(context).platform)}',
            onPressed: _handlePayment,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckoutCareChecklistCard() {
    const quickOptions = [
      '💊 Control de medicación',
      '🍲 Preparar comida / cena',
      '🚶 Paseo de 30-40 min',
      '🧠 Estimulación y compañía',
      '🚿 Apoyo en higiene personal',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primarySurface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.checklist_rtl_rounded, color: AppTheme.primary, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Checklist para el Cuidador (Personalizable)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.darkSlate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Indica las tareas específicas que necesita tu familiar durante el servicio. El cuidador las marcará en tiempo real desde su app.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
          ),
          const SizedBox(height: 12),
          if (_customChecklist.isNotEmpty) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final maxLabelWidth =
                    (constraints.maxWidth - 96).clamp(80.0, double.infinity);
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _customChecklist.map((task) {
                    return Chip(
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      backgroundColor: Colors.white,
                      label: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxLabelWidth),
                        child: Text(
                          task,
                          softWrap: true,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      deleteIcon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppTheme.slateMuted,
                      ),
                      deleteButtonTooltipMessage: 'Quitar tarea $task',
                      onDeleted: () {
                        setState(() => _customChecklist.remove(task));
                      },
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          Builder(
            builder: (context) {
              final seniorMode = context.read<ConfigNotifier>().seniorMode;
              final stackChecklistInput =
                  seniorMode || MediaQuery.textScalerOf(context).scale(1) > 1.2;
              void submitTask() {
                final text = _taskCtrl.text.trim();
                if (text.isNotEmpty && !_customChecklist.contains(text)) {
                  setState(() {
                    _customChecklist.add(text);
                    _taskCtrl.clear();
                  });
                }
              }

              final inputField = TextField(
                controller: _taskCtrl,
                onSubmitted: (_) => submitTask(),
                decoration: InputDecoration(
                  labelText: 'Nueva tarea para el cuidador',
                  hintText: 'Ej. Pastilla a las 12:30...',
                  isDense: !stackChecklistInput,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );

              if (stackChecklistInput) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    inputField,
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: submitTask,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Añadir tarea'),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: inputField),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: submitTask,
                    child: const Text('Añadir'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxQuickWidth =
                  (constraints.maxWidth - 56).clamp(80.0, double.infinity);
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: quickOptions
                    .where((o) => !_customChecklist.contains(o))
                    .map((opt) => ActionChip(
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          backgroundColor: Colors.white,
                          label: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxQuickWidth),
                            child: Text(
                              '+ $opt',
                              softWrap: true,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          onPressed: () {
                            setState(() => _customChecklist.add(opt));
                          },
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

