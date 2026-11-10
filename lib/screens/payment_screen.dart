import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  const PaymentScreen({super.key, required this.caregiver, required this.dateString, required this.slots});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _isLoading = true;
  bool _isProcessingPayment = false;
  int _accumulatedHours = 0;
  bool _applyPackDiscount = false;
  List<String> _customChecklist = [];
  final TextEditingController _taskCtrl = TextEditingController();

  // Tracks booking IDs created in Firestore so we can delete them on rollback.
  final List<String> _createdBookingIds = [];

  @override
  void initState() {
    super.initState();
    final client = context.read<AuthNotifier>().currentClient;
    _customChecklist = List<String>.from(client?.defaultCareChecklist ?? []);
    _applyPackDiscount = widget.slots.length >= 4;
    _loadStats();
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final auth = context.read<AuthNotifier>();
      final clientId = auth.currentUserId ?? 'unknown';
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
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 4),
    ));
  }

  /// Rolls back any slots and bookings already created when payment fails or is
  /// cancelled. Runs best-effort: errors are logged but never shown to the user.
  Future<void> _rollback() async {
    debugPrint('Payment rollback: reverting ${widget.slots.length} slot(s) '
        'and ${_createdBookingIds.length} booking(s).');

    // 1. Re-open the time slots
    for (final s in widget.slots) {
      try {
        s.isAvailable = true;
        await DependencyInjection.caregivers
            .updateTimeSlot(widget.caregiver.id, widget.dateString, s);
      } catch (e) {
        debugPrint('Rollback: failed to restore slot ${s.dateTime}: $e');
      }
    }

    // 2. Delete the pending-payment bookings from Firestore
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
    // ── 0. Capture all context-dependent objects BEFORE any async gap ──
    final auth = context.read<AuthNotifier>();
    final bookingState = context.read<BookingNotifier>();
    final location = context.read<LocationNotifier>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final clientId = auth.currentUserId ?? 'unknown';
    final double caregiverCommissionRate =
        FirestoreStatsRepository.calculateCommissionRate(_accumulatedHours);
    final int totalHours = widget.slots.length;
    final double discountMultiplier = _applyPackDiscount ? 0.95 : 1.0;
    final double baseCost = widget.caregiver.pricePerHour * totalHours * discountMultiplier;
    final double total = baseCost * 1.03;

    _safeSetState(() => _isProcessingPayment = true);

    // ── 1. Connectivity check ──
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        _safeSetState(() => _isProcessingPayment = false);
        _showSnackBar(scaffoldMessenger,
            'Sin conexión a internet. No se puede procesar el pago.', Colors.red);
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
        Colors.orange,
      );
      return;
    }

    // ── 2.5 Verify that selected slots are still available (Anti-Race Condition) ──
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
            Colors.orange.shade800,
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('Slot verification warning: $e');
    }

    // ── 3. Create Payment Intent ──
    Map<String, dynamic>? paymentIntentData;
    try {
      paymentIntentData = await StripeService.createPaymentIntentOnly(
        amountInCents: (total * 100).toInt(),
        currency: 'eur',
        caregiverStripeAccountId: stripeAccountId,
      );
    } catch (e) {
      debugPrint('Error creating payment intent: $e');
      _safeSetState(() => _isProcessingPayment = false);
      _showSnackBar(
          scaffoldMessenger,
          'Error al conectar con el servidor de pagos. Inténtalo de nuevo.',
          Colors.red);
      return;
    }

    if (paymentIntentData == null || paymentIntentData['clientSecret'] == null) {
      _safeSetState(() => _isProcessingPayment = false);
      _showSnackBar(
          scaffoldMessenger,
          'No se pudo inicializar el pago. Inténtalo de nuevo.',
          Colors.red);
      return;
    }

    // ── 4. Initialize Stripe Payment Sheet ──
    bool sheetInitialized = false;
    try {
      sheetInitialized = await StripeService.initPaymentSheet(paymentIntentData);
    } catch (e) {
      debugPrint('Error initializing payment sheet: $e');
      _safeSetState(() => _isProcessingPayment = false);
      if (mounted) {
        CustomDialog.showError(context, title: 'Error de inicialización', message: e.toString());
      }
      return;
    }

    if (!sheetInitialized) {
      _safeSetState(() => _isProcessingPayment = false);
      _showSnackBar(
          scaffoldMessenger,
          'Error desconocido al preparar la pantalla.',
          Colors.red);
      return;
    }

    final transferGroup = paymentIntentData['transferGroup'] ??
        'booking_${DateTime.now().millisecondsSinceEpoch}';
    final paymentIntentId = paymentIntentData['paymentIntentId']?.toString();

    // ── 5. Create bookings in Firestore (pendingPayment) ──
    final String generatedPin = (Random().nextInt(9000) + 1000).toString();

    try {
      // 5.1 Mark all slots as unavailable in Firestore
      for (var s in widget.slots) {
        s.isAvailable = false;
        await DependencyInjection.caregivers
            .updateTimeSlot(widget.caregiver.id, widget.dateString, s);
      }

      // 5.2 Sort slots chronologically
      final sortedSlots = List<TimeSlot>.from(widget.slots)
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

      // 5.3 Group contiguous slots (1 hour apart)
      List<List<TimeSlot>> groupedSlots = [];
      List<TimeSlot> currentGroup = [];

      for (var s in sortedSlots) {
        if (currentGroup.isEmpty) {
          currentGroup.add(s);
        } else {
          final lastSlot = currentGroup.last;
          final diff = s.dateTime.difference(lastSlot.dateTime);
          // Standard slot difference is 60 minutes. Allow slight leniency if needed, but exact is fine here.
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

      // 5.4 Create one Booking per group
      for (var group in groupedSlots) {
        final startSlot = group.first;
        final endSlot = group.last;
        final endDateTime = endSlot.dateTime.add(const Duration(hours: 1));

        final startTimeStr = '${startSlot.dateTime.hour.toString().padLeft(2, '0')}:${startSlot.dateTime.minute.toString().padLeft(2, '0')}';
        final endTimeStr = '${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}';
        
        // If it's multiple hours, create a range (e.g. 10:00-13:00). If it's a single hour, we can still use a range for consistency, or just the start time. 
        // We will use the range universally to ensure consistent parsing downstream.
        final slotRangeStr = '$startTimeStr-$endTimeStr';

        final groupHours = group.length;
        final groupCost = widget.caregiver.pricePerHour * groupHours * discountMultiplier;
        final groupClientFee = groupCost * 0.03;
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
          caregiverCommissionRate: caregiverCommissionRate,
          caregiverCommissionAmount: groupCommission,
          caregiverPayout: groupPayout,
          totalPaid: groupTotalPaid,
          transferGroup: transferGroup,
          paymentIntentId: paymentIntentId,
          clientLatitude: location.latitude,
          clientLongitude: location.longitude,
          bookingPin: generatedPin,
          status: BookingStatus.pendingPayment,
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
      debugPrint('Error creating bookings: $e');
      // Rollback whatever was already created before showing the error
      await _rollback();
      _safeSetState(() => _isProcessingPayment = false);
      if (mounted) {
        CustomDialog.showError(context, title: 'Error al crear la reserva', message: 'No se pudo registrar la reserva. El pago NO ha sido procesado.\n\nDetalles: $e');
      }
      return;
    }

    // ── 6. Show Stripe Payment Sheet ──
    _safeSetState(() => _isProcessingPayment = false);

    String paymentResult;
    try {
      paymentResult = await StripeService.presentPaymentSheet();
    } catch (e) {
      debugPrint('Unexpected error presenting payment sheet: $e');
      paymentResult = 'error';
    }

    // ── 7. Handle result ──
    switch (paymentResult) {
      case 'success':
        // Payment confirmed — update bookings to pending and clear rollback list
        for (final id in _createdBookingIds) {
          try {
            await DependencyInjection.bookings.updateBookingStatus(id, 'pending');
          } catch (e) {
            debugPrint('Failed to update booking status to pending: $e');
          }
        }
        _createdBookingIds.clear();
        if (mounted) {
          HapticFeedback.heavyImpact();
          await _showBookingSuccessModal(context, total, generatedPin);
        }
        navigator.popUntil((route) => route.isFirst);

      case 'cancelled':
        // User dismissed the sheet — roll back so they can try again
        await _rollback();
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'Pago no completado',
            message: 'Has cerrado la pasarela de pago. Tu reserva no se ha cobrado. Puedes volver a intentarlo con tarjeta o en 1 toque con Apple Pay / Google Pay.',
          );
        }

      default:
        // Payment failed — roll back so they can retry with different card
        await _rollback();
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'Operación denegada por el banco',
            message: 'No se ha podido completar el cargo o la verificación 3D Secure. Revisa los datos de tu tarjeta o utiliza Apple Pay / Google Pay.',
          );
        }
    }
  }

  Future<void> _showBookingSuccessModal(BuildContext context, double totalPaid, String pin) async {
    final dateFormatted = DateFormat('dd/MM/yyyy').format(DateTime.parse(widget.dateString));
    final hoursStr = widget.slots
        .map((s) => '${s.dateTime.hour.toString().padLeft(2, '0')}:${s.dateTime.minute.toString().padLeft(2, '0')}')
        .join(', ');
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(22),
        content: Column(
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
              'Tu pago de ${totalPaid.toStringAsFixed(2)} € está protegido en custodia bancaria (Stripe Escrow). Solo se liberará a ${widget.caregiver.name} tras realizar el cuidado.',
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
                label: const Text('Compartir recibo y PIN por WhatsApp'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Finalizar e ir al Inicio'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManagementFeeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
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
                    '¿Qué incluye el 3% de Gestión y Cobertura?',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('• 🛡️ Seguro de Responsabilidad Civil hasta 500.000€ durante toda la estancia en el domicilio.', style: TextStyle(fontSize: 13.5, height: 1.4)),
            const SizedBox(height: 8),
            const Text('• 🔐 Custodia Bancaria Stripe Escrow: tu dinero no se transfiere al cuidador hasta que se verifica su llegada con PIN/QR.', style: TextStyle(fontSize: 13.5, height: 1.4)),
            const SizedBox(height: 8),
            const Text('• 🎧 Soporte prioritario, sustitución urgente y mediación familiar 7 días a la semana.', style: TextStyle(fontSize: 13.5, height: 1.4)),
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

    final int totalHours = widget.slots.length;
    final double rawBaseCost = widget.caregiver.pricePerHour * totalHours;
    final double packDiscountAmount = _applyPackDiscount ? rawBaseCost * 0.05 : 0.0;
    final double baseCost = rawBaseCost - packDiscountAmount;
    final double clientFee = baseCost * 0.03;
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
                const Text('📦', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bono Familiar Multi-Sesión (-5% dto.)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.darkSlate),
                      ),
                      Text(
                        _applyPackDiscount
                            ? 'Ahorras ${currencyFormat.format(packDiscountAmount)} en esta reserva por planificar tu cuidado'
                            : 'Activa el pack familiar semanal para ahorrar un 5% en los honorarios',
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _applyPackDiscount,
                  activeThumbColor: AppTheme.secondaryColor,
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    setState(() => _applyPackDiscount = val);
                  },
                ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cuidador:'),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.caregiver.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Horarios:'),
                      Flexible(
                        child: Text(
                          widget.slots
                              .map((s) =>
                                  '${s.dateTime.hour.toString().padLeft(2, '0')}:${s.dateTime.minute.toString().padLeft(2, '0')}')
                              .join(', '),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Duración:'),
                      Text(
                        '$totalHours hora${totalHours > 1 ? 's' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Honorarios del cuidador:'),
                      Text(currencyFormat.format(rawBaseCost)),
                    ],
                  ),
                  if (_applyPackDiscount) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📦 Descuento Bono Familiar (-5%):',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.secondaryColor),
                        ),
                        Text(
                          '-${currencyFormat.format(packDiscountAmount)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.secondaryColor),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: () => _showManagementFeeSheet(context),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  '3% Comisión de Gestión y Cobertura:',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.primary),
                            ],
                          ),
                        ),
                      ),
                      Text(currencyFormat.format(clientFee),
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
          _buildCheckoutCareChecklistCard(),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.green.shade50,
            child: const Row(
              children: [
                Icon(Icons.verified_user, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pago 100% Seguro. Tu dinero está protegido por Stripe Escrow hasta que finalice el servicio y confirmes que todo ha ido bien.',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pagos por servicios asistenciales presenciales a domicilio (exentos de IAP digital conforme a App Store Guideline 3.1.5 / Google Play). El importe queda retenido en garantía (Stripe Escrow) y solo se transfiere a ${widget.caregiver.name.split(' ')[0]} tras realizar el servicio y validar su llegada.',
                    style: const TextStyle(color: Colors.blue, height: 1.5),
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
          child: ElevatedButton.icon(
            onPressed: _isProcessingPayment ? null : _handlePayment,
            icon: _isProcessingPayment
                ? const SizedBox.shrink()
                : const Icon(Icons.lock_rounded, size: 18),
            label: _isProcessingPayment
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Pagar con Apple Pay / Google Pay / Tarjeta'),
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _customChecklist.map((task) {
                return Chip(
                  backgroundColor: Colors.white,
                  label: Text(task, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  onDeleted: () {
                    setState(() => _customChecklist.remove(task));
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _taskCtrl,
                  decoration: InputDecoration(
                    hintText: 'Añadir tarea específica (ej. Pastilla 12:30)...',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final text = _taskCtrl.text.trim();
                  if (text.isNotEmpty && !_customChecklist.contains(text)) {
                    setState(() {
                      _customChecklist.add(text);
                      _taskCtrl.clear();
                    });
                  }
                },
                child: const Text('Añadir'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: quickOptions
                .where((o) => !_customChecklist.contains(o))
                .map((opt) => ActionChip(
                      backgroundColor: Colors.white,
                      label: Text('+ $opt', style: const TextStyle(fontSize: 11.5)),
                      onPressed: () {
                        setState(() => _customChecklist.add(opt));
                      },
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

