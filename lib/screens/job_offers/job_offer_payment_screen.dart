import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
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
        _showSnackBar(scaffoldMessenger, 'Pago cancelado.', Colors.orange);
        return;
      } else if (paymentResult == 'error') {
        _safeSetState(() => _isProcessing = false);
        _showSnackBar(scaffoldMessenger, 'Ha ocurrido un error durante el pago.', Colors.red);
        return;
      }

      // 5. Payment Success -> Update DB
      if (!mounted) return;
      // Update application and offer statuses
      await context.read<JobOfferNotifier>().acceptApplication(widget.offer.id, widget.application.id, widget.application.caregiverId);

      // Create booking(s)
      final paymentIntentId = paymentIntentData['paymentIntentId'] as String? ?? '';
      
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
            final commissionRate = 0.18 - widget.offer.urgencyBonusRate;
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
              bookingPin: (Random().nextInt(9000) + 1000).toString(),
              createdAt: DateTime.now(),
              paymentIntentId: paymentIntentId,
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
        final commissionRate = 0.18 - widget.offer.urgencyBonusRate;
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
          bookingPin: (Random().nextInt(9000) + 1000).toString(),
          createdAt: DateTime.now(),
          paymentIntentId: paymentIntentId,
        );
        await DependencyInjection.bookings.createBooking(booking);
      }

      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
        CustomSnackBar.show(context, message: 'Pago realizado y cuidador contratado.', type: SnackBarType.success);
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
            trailing: Text('${widget.application.proposedPrice} €/h'),
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
            title: const Text('Comisión plataforma (5%)'),
            trailing: Text('${fee.toStringAsFixed(2)} €'),
          ),
          ListTile(
            title: const Text('Total a pagar', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Text('${total.toStringAsFixed(2)} €', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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




