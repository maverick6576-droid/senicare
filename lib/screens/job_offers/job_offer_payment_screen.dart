import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int _accumulatedHours = 0;
  List<String> _customChecklist = [];
  final TextEditingController _taskCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthNotifier>();
    final client = auth.currentClient;
    _customChecklist = List<String>.from(client?.defaultCareChecklist ?? []);
    _loadAccumulatedHours(auth.currentUserId);
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
    
    _safeSetState(() => _isProcessing = true);

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
      final total = subtotal + fee;

      // 2. Create Payment Intent
      Map<String, dynamic>? paymentIntentData;
      try {
        paymentIntentData = await StripeService.createPaymentIntentOnly(
          amountInCents: (total * 100).toInt(),
          currency: 'eur',
          caregiverStripeAccountId: stripeAccountId,
        );
      } catch (e) {
        _safeSetState(() => _isProcessing = false);
        _showSnackBar(scaffoldMessenger, e.toString().replaceAll('Exception: ', ''), Colors.red);
        return;
      }

      if (paymentIntentData == null) {
        _safeSetState(() => _isProcessing = false);
        _showSnackBar(scaffoldMessenger, 'Error inesperado al crear el pago.', Colors.red);
        return;
      }

      // 3. Initialize Stripe Payment Sheet
      bool sheetInitialized = false;
      try {
        sheetInitialized = await StripeService.initPaymentSheet(paymentIntentData);
      } catch (e) {
        debugPrint('Error initializing payment sheet: $e');
        _safeSetState(() => _isProcessing = false);
        if (mounted) {
          CustomDialog.showError(context, title: 'Error de inicialización', message: e.toString());
        }
        return;
      }

      if (!sheetInitialized) {
        _safeSetState(() => _isProcessing = false);
        _showSnackBar(scaffoldMessenger, 'Error al preparar la pantalla de pago.', Colors.red);
        return;
      }

      // 4. Present Payment Sheet
      final paymentResult = await StripeService.presentPaymentSheet();
      if (paymentResult == 'cancelled') {
        _safeSetState(() => _isProcessing = false);
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'Pago no completado',
            message: 'Has cerrado la ventana de pago antes de finalizar. Puedes intentarlo de nuevo con tu tarjeta o en 1 toque con Apple Pay / Google Pay.',
          );
        }
        return;
      } else if (paymentResult == 'error') {
        _safeSetState(() => _isProcessing = false);
        if (mounted) {
          CustomDialog.showError(
            context,
            title: 'Operación denegada por el banco',
            message: 'No se ha podido completar el cargo o la verificación 3D Secure. Revisa los datos de tu tarjeta o prueba con Apple Pay / Google Pay.',
          );
        }
        return;
      }

      // 5. Payment Success -> Update DB
      if (!mounted) return;
      // Update application and offer statuses
      await context.read<JobOfferNotifier>().acceptApplication(widget.offer.id, widget.application.id, widget.application.caregiverId);

      // Create booking(s)
      final paymentIntentId = paymentIntentData['paymentIntentId'] as String? ?? '';
      final double baseTierRate = FirestoreStatsRepository.calculateCommissionRate(_accumulatedHours);
      final double effectiveCommissionRate = (baseTierRate - widget.offer.urgencyBonusRate).clamp(0.05, 0.18);
      final String generatedPin = (Random().nextInt(9000) + 1000).toString();
      
      if (widget.offer.isRecurring) {
        final List<Booking> bookings = [];
        final totalDays = widget.offer.recurringWeeks * 7;
        
        for (int i = 0; i < totalDays; i++) {
          final targetDate = widget.offer.startDate.add(Duration(days: i));
          if (widget.offer.recurringDaysOfWeek.contains(targetDate.weekday)) {
            final startDateTime = DateTime(targetDate.year, targetDate.month, targetDate.day, int.parse(widget.offer.recurringStartTime.split(':')[0]), int.parse(widget.offer.recurringStartTime.split(':')[1]));
            final endDateTime = startDateTime.add(Duration(hours: widget.offer.recurringHoursPerDay));
            
            final cost = widget.offer.recurringHoursPerDay * widget.application.proposedPrice;
            final clientFee = cost * widget.offer.clientFeeRate;
            final commissionRate = effectiveCommissionRate;
            final commissionAmount = cost * commissionRate;
            final payout = cost - commissionAmount;

            bookings.add(Booking(
              id: '',
              clientId: auth.currentUserId ?? '',
              caregiverId: widget.application.caregiverId,
              caregiverName: widget.application.caregiverName,
              day: '${startDateTime.year}-${startDateTime.month.toString().padLeft(2, '0')}-${startDateTime.day.toString().padLeft(2, '0')}',
              slot: '${startDateTime.hour.toString().padLeft(2, '0')}:${startDateTime.minute.toString().padLeft(2, '0')}-${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}',
              cost: cost,
              clientFee: clientFee,
              caregiverCommissionRate: commissionRate,
              caregiverCommissionAmount: commissionAmount,
              caregiverPayout: payout,
              totalPaid: cost + clientFee,
              status: BookingStatus.confirmed,
              bookingPin: generatedPin,
              createdAt: DateTime.now(),
              paymentIntentId: paymentIntentId,
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
        
        for (var b in bookings) {
          await DependencyInjection.bookings.createBooking(b);
        }
      } else {
        final endDateTime = widget.offer.startDate.add(Duration(hours: widget.offer.totalHours));
        final cost = widget.offer.totalHours * widget.application.proposedPrice;
        final clientFee = cost * widget.offer.clientFeeRate;
        final commissionRate = effectiveCommissionRate;
        final commissionAmount = cost * commissionRate;
        final payout = cost - commissionAmount;

        final booking = Booking(
          id: '',
          clientId: auth.currentUserId ?? '',
          caregiverId: widget.application.caregiverId,
          caregiverName: widget.application.caregiverName,
          day: '${widget.offer.startDate.year}-${widget.offer.startDate.month.toString().padLeft(2, '0')}-${widget.offer.startDate.day.toString().padLeft(2, '0')}',
          slot: '${widget.offer.startDate.hour.toString().padLeft(2, '0')}:${widget.offer.startDate.minute.toString().padLeft(2, '0')}-${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}',
          cost: cost,
          clientFee: clientFee,
          caregiverCommissionRate: commissionRate,
          caregiverCommissionAmount: commissionAmount,
          caregiverPayout: payout,
          totalPaid: cost + clientFee,
          status: BookingStatus.confirmed,
          bookingPin: generatedPin,
          createdAt: DateTime.now(),
          paymentIntentId: paymentIntentId,
          clientLatitude: widget.offer.clientLatitude,
          clientLongitude: widget.offer.clientLongitude,
          careChecklist: _customChecklist
              .asMap()
              .entries
              .map((e) => CareChecklistItem(id: 'task_${e.key + 1}', title: e.value))
              .toList(),
        );
        await DependencyInjection.bookings.createBooking(booking);
      }

      if (mounted) {
        HapticFeedback.heavyImpact();
        await _showSuccessReceiptModal(context, total, generatedPin);
        if (mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    } catch (e) {
      debugPrint('Error processing payment: $e');
      if (mounted) {
        _showSnackBar(scaffoldMessenger, 'Error al procesar el pago: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showSuccessReceiptModal(BuildContext context, double totalPaid, String pin) async {
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
              'Tu pago de ${totalPaid.toStringAsFixed(2)} € está protegido en Stripe Escrow hasta que ${widget.application.caregiverName} complete el cuidado.',
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
    final subtotal = widget.offer.totalHours * widget.application.proposedPrice;
    final fee = subtotal * widget.offer.clientFeeRate;
    final total = subtotal + fee;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar y Pagar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Resumen del servicio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ListTile(
            title: Text(widget.offer.title),
            subtitle: Text('Cuidador: ${widget.application.caregiverName}'),
          ),
          ListTile(
            title: const Text('Precio acordado'),
            trailing: Text('${widget.application.proposedPrice.toStringAsFixed(2)} €/h'),
          ),
          ListTile(
            title: const Text('Total horas'),
            trailing: Text('${widget.offer.totalHours}h'),
          ),
          const Divider(),
          ListTile(
            title: const Text('Subtotal'),
            trailing: Text('${subtotal.toStringAsFixed(2)} €'),
          ),
          ListTile(
            title: Row(
              children: [
                Flexible(
                  child: Text('${(widget.offer.clientFeeRate * 100).toInt()}% Comisión de Gestión y Cobertura'),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _showFeeInfoSheet(context),
                  child: const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primary),
                ),
              ],
            ),
            trailing: Text('${fee.toStringAsFixed(2)} €'),
          ),
          ListTile(
            title: const Text('Total a pagar', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Text('${total.toStringAsFixed(2)} €', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                const Text(
                  '📋 Checklist de Cuidado para esta Oferta',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.darkSlate),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tareas que el cuidador marcará en tiempo real durante la visita:',
                  style: TextStyle(fontSize: 12, color: AppTheme.slateMuted),
                ),
                const SizedBox(height: 8),
                if (_customChecklist.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _customChecklist
                        .map((t) => Chip(
                              backgroundColor: Colors.white,
                              label: Text(t, style: const TextStyle(fontSize: 12)),
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
                        decoration: InputDecoration(
                          hintText: 'Añadir tarea (ej. Medicación, paseo)...',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final val = _taskCtrl.text.trim();
                        if (val.isNotEmpty && !_customChecklist.contains(val)) {
                          setState(() {
                            _customChecklist.add(val);
                            _taskCtrl.clear();
                          });
                        }
                      },
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
              child: const Text('Al ser un servicio recurrente, este pago retiene el importe total. Se irá liberando al cuidador a medida que se completen las sesiones.', style: TextStyle(color: Colors.blue)),
            ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _isProcessing ? null : _processPayment,
            child: _isProcessing ? const CircularProgressIndicator(color: Colors.white) : Text('Pagar ${total.toStringAsFixed(2)} €'),
          ),
        ],
      ),
    );
  }
}




