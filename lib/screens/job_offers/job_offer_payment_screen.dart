import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/firebase/firestore_stats_repository.dart';
import 'package:senicare/widgets/widgets.dart';
import 'dart:math';

class JobOfferPaymentScreen extends StatefulWidget {
  final JobOffer offer;
  final JobApplication application;

  const JobOfferPaymentScreen({super.key, required this.offer, required this.application});

  @override
  State<JobOfferPaymentScreen> createState() => _JobOfferPaymentScreenState();
}

class _JobOfferPaymentScreenState extends State<JobOfferPaymentScreen> {
  bool _isProcessing = false;
  bool _platformPaySupported = false;
  ClientPaymentMethod _selectedPaymentMethod = ClientPaymentMethod.platformPay;
  int _accumulatedHours = 0;
  List<String> _customChecklist = [];
  final TextEditingController _taskCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthNotifier>();
    final client = auth.currentClient;
    _customChecklist = List<String>.from(client?.defaultCareChecklist ?? []);
    _loadAccumulatedHours(auth.effectiveClientId);
    _detectPlatformPay();
  }

  Future<void> _detectPlatformPay() async {
    final supported = await StripeService.isPlatformPaySupported();
    if (mounted) {
      setState(() => _platformPaySupported = supported);
    }
  }

  Future<void> _loadAccumulatedHours(String? clientId) async {
    if (clientId == null || clientId.isEmpty) return;
    try {
      final hrs = await DependencyInjection.stats.getAccumulatedHours(
        clientId,
        widget.application.caregiverId,
      );
      if (mounted) setState(() => _accumulatedHours = hrs);
    } catch (_) {}
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _showSnackBar(ScaffoldMessengerState messenger, String message, Color color) {
    messenger.showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _processPayment() async {
    final auth = context.read<AuthNotifier>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final clientId = auth.effectiveClientId;
    if (!auth.canManageFamilyPayments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solo un Administrador de la familia puede confirmar pagos de ofertas.',
          ),
        ),
      );
      return;
    }

    if (clientId == null || clientId.isEmpty) {
      _showSnackBar(scaffoldMessenger, 'Debes iniciar sesión para confirmar el pago.', Colors.red);
      return;
    }

    if (widget.offer.totalHours <= 0 || widget.application.proposedPrice <= 0) {
      _showSnackBar(scaffoldMessenger, 'El importe de la oferta no es válido.', Colors.red);
      return;
    }

    _safeSetState(() => _isProcessing = true);

    String? chargedPaymentIntentId;
    try {
      // 1. Fetch caregiver to get stripeAccountId
      final caregiver = await DependencyInjection.caregivers.getCaregiver(widget.application.caregiverId);
      if (caregiver == null) {
        _safeSetState(() => _isProcessing = false);
        _showSnackBar(scaffoldMessenger, 'Error al cargar los datos del cuidador.', Colors.red);
        return;
      }

      final stripeAccountId = caregiver.stripeAccountId;
      if (stripeAccountId == null || stripeAccountId.isEmpty) {
        _safeSetState(() => _isProcessing = false);
        _showSnackBar(
          scaffoldMessenger,
          'Este cuidador aún no ha configurado su cuenta de pago. Contacta con soporte.',
          Colors.orange,
        );
        return;
      }

      final subtotal = widget.offer.totalHours * widget.application.proposedPrice;
      final fee = subtotal * widget.offer.clientFeeRate;
      double total = subtotal + fee;

      final List<Map<String, dynamic>> serverSessions = [];
      final List<Booking> draftBookings = [];
      final double baseTierRate = FirestoreStatsRepository.calculateCommissionRate(_accumulatedHours);
      final double effectiveCommissionRate = (baseTierRate - widget.offer.urgencyBonusRate).clamp(0.05, 0.18);
      String generatedPin = (Random().nextInt(9000) + 1000).toString();
      final List<String> createdBookingIds = [];
      Map<String, dynamic> paymentIntentData = {
        'transferGroup': 'offer_${widget.offer.id}_${DateTime.now().millisecondsSinceEpoch}',
      };
      String transferGroup = paymentIntentData['transferGroup'].toString();

      Future<void> rollbackDrafts() async {
        if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
          await StripeService.cancelPendingCheckout(
            List<String>.from(createdBookingIds),
          );
          createdBookingIds.clear();
          return;
        }
        for (final id in createdBookingIds) {
          try {
            await DependencyInjection.bookings.deleteBooking(id);
          } catch (e) {
            debugPrint('Rollback job offer booking failed ($id): $e');
          }
        }
        createdBookingIds.clear();
      }

      if (widget.offer.isRecurring) {
        final totalDays = widget.offer.recurringWeeks * 7;
        for (int i = 0; i < totalDays; i++) {
          final targetDate = widget.offer.startDate.add(Duration(days: i));
          if (widget.offer.recurringDaysOfWeek.contains(targetDate.weekday)) {
            int startHour = 9;
            int startMinute = 0;
            if (widget.offer.recurringStartTime.contains(':')) {
              final timeParts = widget.offer.recurringStartTime.split(':');
              startHour = int.tryParse(timeParts[0]) ?? 9;
              startMinute = int.tryParse(timeParts[1]) ?? 0;
            }
            final startDateTime = DateTime(targetDate.year, targetDate.month, targetDate.day, startHour, startMinute);
            final endDateTime = startDateTime.add(Duration(hours: widget.offer.recurringHoursPerDay));
            final dayStr = '${startDateTime.year}-${startDateTime.month.toString().padLeft(2, '0')}-${startDateTime.day.toString().padLeft(2, '0')}';
            final slotStr = '${startDateTime.hour.toString().padLeft(2, '0')}:${startDateTime.minute.toString().padLeft(2, '0')}-${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}';

            serverSessions.add({
              'day': dayStr,
              'slot': slotStr,
              'totalHours': widget.offer.recurringHoursPerDay,
            });

            final cost = widget.offer.recurringHoursPerDay * widget.application.proposedPrice;
            final clientFee = cost * widget.offer.clientFeeRate;
            final commissionAmount = cost * effectiveCommissionRate;
            final payout = cost - commissionAmount;

            draftBookings.add(Booking(
              id: '',
              clientId: auth.effectiveClientId ?? '',
              caregiverId: widget.application.caregiverId,
              caregiverName: widget.application.caregiverName,
              day: dayStr,
              slot: slotStr,
              cost: cost,
              clientFee: clientFee,
              clientFeeRate: widget.offer.clientFeeRate,
              caregiverCommissionRate: effectiveCommissionRate,
              caregiverCommissionAmount: commissionAmount,
              caregiverPayout: payout,
              totalPaid: cost + clientFee,
              status: BookingStatus.pendingPayment,
              escrowStatus: 'none',
              bookingPin: generatedPin,
              createdAt: DateTime.now(),
              transferGroup: transferGroup,
              paymentIntentId: null,
              paymentMethodType: _selectedPaymentMethod.backendId,
              paymentStatus: 'pending',
              clientLatitude: widget.offer.clientLatitude,
              clientLongitude: widget.offer.clientLongitude,
              careChecklist: _customChecklist
                  .asMap()
                  .entries
                  .map((e) => CareChecklistItem(id: 'task_${e.key + 1}', title: e.value))
                  .toList(),
            ));
          }
        }
      } else {
        final endDateTime = widget.offer.startDate.add(Duration(hours: widget.offer.totalHours));
        final dayStr = '${widget.offer.startDate.year}-${widget.offer.startDate.month.toString().padLeft(2, '0')}-${widget.offer.startDate.day.toString().padLeft(2, '0')}';
        final slotStr = '${widget.offer.startDate.hour.toString().padLeft(2, '0')}:${widget.offer.startDate.minute.toString().padLeft(2, '0')}-${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}';

        serverSessions.add({
          'day': dayStr,
          'slot': slotStr,
          'totalHours': widget.offer.totalHours,
        });

        final cost = widget.offer.totalHours * widget.application.proposedPrice;
        final clientFee = cost * widget.offer.clientFeeRate;
        final commissionAmount = cost * effectiveCommissionRate;
        final payout = cost - commissionAmount;

        draftBookings.add(Booking(
          id: '',
          clientId: auth.effectiveClientId ?? '',
          caregiverId: widget.application.caregiverId,
          caregiverName: widget.application.caregiverName,
          day: dayStr,
          slot: slotStr,
          cost: cost,
          clientFee: clientFee,
          clientFeeRate: widget.offer.clientFeeRate,
          caregiverCommissionRate: effectiveCommissionRate,
          caregiverCommissionAmount: commissionAmount,
          caregiverPayout: payout,
          totalPaid: cost + clientFee,
          status: BookingStatus.pendingPayment,
          escrowStatus: 'none',
          bookingPin: generatedPin,
          createdAt: DateTime.now(),
          transferGroup: transferGroup,
          paymentIntentId: null,
          paymentMethodType: _selectedPaymentMethod.backendId,
          paymentStatus: 'pending',
          clientLatitude: widget.offer.clientLatitude,
          clientLongitude: widget.offer.clientLongitude,
          careChecklist: _customChecklist
              .asMap()
              .entries
              .map((e) => CareChecklistItem(id: 'task_${e.key + 1}', title: e.value))
              .toList(),
        ));
      }

      if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
        try {
          final created = await StripeService.createSecureBooking(
            caregiverId: widget.application.caregiverId,
            offerId: widget.offer.id,
            applicationId: widget.application.id,
            familyId: clientId,
            preferredMethod: _selectedPaymentMethod.backendId,
            useCheckoutSession: _selectedPaymentMethod.usesExternalCheckout,
            sessions: serverSessions,
            clientLatitude: widget.offer.clientLatitude,
            clientLongitude: widget.offer.clientLongitude,
            checklist: _customChecklist,
          );
          paymentIntentData = created;
          transferGroup = created['transferGroup']?.toString() ?? transferGroup;
          generatedPin = created['bookingPin']?.toString() ?? generatedPin;
          final serverTotal = (created['totalEur'] as num?)?.toDouble();
          if (serverTotal != null && serverTotal > 0) {
            total = serverTotal;
          }
          final rawIds = created['bookingIds'] as List<dynamic>? ?? [];
          createdBookingIds.addAll(rawIds.map((e) => e.toString()).where((e) => e.isNotEmpty));
          if (createdBookingIds.isEmpty) {
            throw Exception('El servidor no devolvió reservas válidas.');
          }
        } catch (e) {
          _safeSetState(() => _isProcessing = false);
          _showSnackBar(scaffoldMessenger, e.toString().replaceFirst('Exception: ', ''), Colors.red);
          return;
        }
      } else {
        try {
          for (final b in draftBookings) {
            final id = await DependencyInjection.bookings.createBooking(b);
            createdBookingIds.add(id);
          }
        } catch (e) {
          await rollbackDrafts();
          _safeSetState(() => _isProcessing = false);
          _showSnackBar(scaffoldMessenger, 'No se pudo preparar la reserva: $e', Colors.red);
          return;
        }
      }

      if (!mounted) return;
      final customerName = auth.currentClient?.name ?? auth.currentUserDisplayName;
      final flowResult = await executeClientStripePayment(
        context: context,
        method: _selectedPaymentMethod,
        platformPaySupported: _platformPaySupported,
        paymentIntentData: paymentIntentData,
        totalEur: total,
        itemLabel: '${widget.offer.title} · ${widget.application.caregiverName}',
        customerEmail: auth.currentUserEmail,
        customerName: customerName,
        caregiverStripeAccountId: stripeAccountId,
        familyId: clientId,
        bookingIds: List<String>.from(createdBookingIds),
      );

      if (flowResult.outcome == 'cancelled') {
        await rollbackDrafts();
        _safeSetState(() => _isProcessing = false);
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'Pago no completado',
            message: 'Has cerrado la ventana de pago antes de finalizar. Puedes intentarlo con Apple Pay, Google Pay, Bizum, Klarna, Tarjeta o SEPA.',
          );
        }
        return;
      } else if (flowResult.outcome == 'error') {
        await rollbackDrafts();
        _safeSetState(() => _isProcessing = false);
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'Operación no completada',
            message: 'No se pudo autorizar el cobro con este método. Revisa tus datos o prueba con Apple Pay, Google Pay, Bizum o Tarjeta.',
          );
        }
        return;
      }

      // 5. Payment Success (or SEPA processing) -> Confirmar en backend y aceptar candidatura
      chargedPaymentIntentId =
          flowResult.paymentIntentId ?? paymentIntentData['paymentIntentId'] as String?;
      if (!mounted) return;
      await context.read<JobOfferNotifier>().acceptApplication(
            widget.offer.id,
            widget.application.id,
            widget.application.caregiverId,
          );

      if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
        try {
          await StripeService.confirmClientBookingPayment(
            bookingIds: createdBookingIds,
            paymentIntentId: chargedPaymentIntentId,
            sessionId: flowResult.sessionId,
            targetStatus: 'confirmed',
            transferGroup: paymentIntentData['transferGroup']?.toString() ?? transferGroup,
          );
        } catch (e) {
          debugPrint('confirmClientBookingPayment warning (offer webhook reconciles): $e');
        }
      } else {
        for (final id in createdBookingIds) {
          await DependencyInjection.bookings.updateBookingStatus(id, 'confirmed');
        }
      }

      if (mounted) {
        HapticFeedback.heavyImpact();
        await _showSuccessReceiptModal(
          context,
          total,
          generatedPin,
          isProcessingBank: flowResult.outcome == 'processing',
        );
        if (mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    } catch (e) {
      debugPrint('Error processing payment: $e');
      if (mounted) {
        final msg = chargedPaymentIntentId != null
            ? 'El pago fue autorizado ($chargedPaymentIntentId), pero hubo un problema al registrar la reserva. Contacta con soporte.'
            : 'No pudimos completar el pago. Inténtalo de nuevo.';
        _showSnackBar(scaffoldMessenger, msg, Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showSuccessReceiptModal(
    BuildContext context,
    double totalPaid,
    String pin, {
    bool isProcessingBank = false,
  }) async {
    final dateFormatted = '${widget.offer.startDate.day.toString().padLeft(2, '0')}/${widget.offer.startDate.month.toString().padLeft(2, '0')}/${widget.offer.startDate.year}';
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(22),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_rounded, color: AppTheme.secondaryColor, size: 48),
            ),
            const SizedBox(height: 14),
            const Text(
              '¡Reserva Confirmada y Asegurada!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
            ),
            const SizedBox(height: 6),
            Text(
              isProcessingBank
                  ? 'Orden SEPA autorizada por ${totalPaid.toStringAsFixed(2)} €. Tu banco la procesará en 1-3 días hábiles bajo custodia Stripe Escrow hasta completar el cuidado con ${widget.application.caregiverName}.'
                  : 'Tu pago de ${totalPaid.toStringAsFixed(2)} € está protegido en Stripe Escrow hasta que ${widget.application.caregiverName} complete el cuidado.',
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
                  final text = '✅ Cuidado confirmado en SeniCare\n'
                      '👩‍⚕️ Cuidador/a: ${widget.application.caregiverName}\n'
                      '📅 Inicio: $dateFormatted (${widget.offer.totalHours}h)\n'
                      '🔑 Código PIN de llegada: $pin\n'
                      '🛡️ Pago protegido en garantía: ${totalPaid.toStringAsFixed(2)} €';
                  await Clipboard.setData(ClipboardData(text: text));
                  if (ctx.mounted) {
                    CustomSnackBar.show(ctx, message: '📋 Resumen y PIN copiados para enviar por WhatsApp a tu familia.', type: SnackBarType.success);
                  }
                },
                icon: const Icon(Icons.share_rounded, size: 17),
                label: const Text('Copiar recibo y PIN para WhatsApp'),
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

  void _showFeeInfoSheet(BuildContext context) {
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
            const Text('• 🎧 Soporte prioritario y mediación familiar 7 días a la semana.', style: TextStyle(fontSize: 13.5, height: 1.4)),
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
    final seniorMode = context.watch<ConfigNotifier>().seniorMode;
    final subtotal = widget.offer.totalHours * widget.application.proposedPrice;
    final fee = subtotal * widget.offer.clientFeeRate;
    final total = subtotal + fee;

    return Scaffold(
      backgroundColor: AppTheme.backgroundNeutral,
      appBar: AppBar(title: const Text('Confirmar y Pagar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.modernCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resumen del cuidado',
                  style: TextStyle(
                    fontSize: seniorMode ? 19 : 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkSlate,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.offer.title,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: seniorMode ? 16.5 : 15),
                  ),
                  subtitle: Text(
                    'Cuidador/a: ${widget.application.caregiverName}',
                    style: TextStyle(fontSize: seniorMode ? 15 : 13.5),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Precio acordado', style: TextStyle(fontSize: seniorMode ? 15.5 : 14)),
                  trailing: Text(
                    '${widget.application.proposedPrice.toStringAsFixed(2)} €/h',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: seniorMode ? 15.5 : 14),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Duración', style: TextStyle(fontSize: seniorMode ? 15.5 : 14)),
                  trailing: Text(
                    '${widget.offer.totalHours}h',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: seniorMode ? 15.5 : 14),
                  ),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Subtotal servicio', style: TextStyle(fontSize: seniorMode ? 15.5 : 14)),
                  trailing: Text(
                    '${subtotal.toStringAsFixed(2)} €',
                    style: TextStyle(fontSize: seniorMode ? 15.5 : 14),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${(widget.offer.clientFeeRate * 100).round()}% Gestión y Seguro RC',
                          style: TextStyle(fontSize: seniorMode ? 15 : 13.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _showFeeInfoSheet(context),
                        child: const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primary),
                      ),
                    ],
                  ),
                  trailing: Text(
                    '${fee.toStringAsFixed(2)} €',
                    style: TextStyle(fontSize: seniorMode ? 15.5 : 14),
                  ),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Total protegido',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: seniorMode ? 18 : 16),
                  ),
                  trailing: Text(
                    '${total.toStringAsFixed(2)} €',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: seniorMode ? 21 : 18.5,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PaymentMethodSelectorCard(
            selectedMethod: _selectedPaymentMethod,
            seniorMode: seniorMode,
            platformPaySupported: _platformPaySupported,
            onChanged: (method) {
              setState(() => _selectedPaymentMethod = method);
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primarySurface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📋 Lista de tareas para la visita (opcional)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: seniorMode ? 16 : 14.5,
                    color: AppTheme.darkSlate,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'El cuidador irá marcando cada punto durante el servicio:',
                  style: TextStyle(fontSize: seniorMode ? 14 : 12.5, color: AppTheme.slateMuted),
                ),
                const SizedBox(height: 8),
                if (_customChecklist.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _customChecklist
                        .map((t) => Chip(
                              backgroundColor: Colors.white,
                              label: Text(t, style: TextStyle(fontSize: seniorMode ? 14 : 12.5)),
                              onDeleted: () => setState(() => _customChecklist.remove(t)),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _taskCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addChecklistItem(),
                        decoration: InputDecoration(
                          hintText: 'Añadir tarea (ej. paseo, comida)...',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addChecklistItem,
                      child: const Text('Añadir'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (widget.offer.isRecurring)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: const Text(
                'Al ser un servicio recurrente, este pago retiene el importe total y se libera conforme se completan las sesiones.',
                style: TextStyle(color: Colors.blue),
              ),
            ),
          const SizedBox(height: 24),
          PrimaryCheckoutActionBar(
            selectedMethod: _selectedPaymentMethod,
            platformPaySupported: _platformPaySupported,
            isProcessing: _isProcessing,
            seniorMode: seniorMode,
            fallbackButtonLabel: 'Confirmar y Pagar ${total.toStringAsFixed(2)} €',
            onPressed: _processPayment,
          ),
        ],
      ),
    );
  }

  void _addChecklistItem() {
    final val = _taskCtrl.text.trim();
    if (val.isNotEmpty && !_customChecklist.contains(val)) {
      setState(() {
        _customChecklist.add(val);
        _taskCtrl.clear();
      });
    }
  }
}




