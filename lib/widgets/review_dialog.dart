import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/widgets.dart';

class ReviewDialog extends StatefulWidget {
  final List<Booking> bookings;

  const ReviewDialog({super.key, required this.bookings});

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  double _rating = 5.0;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Valorar Servicio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Qué te ha parecido el servicio de ${widget.bookings.first.caregiverName}?'),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                    onPressed: () {
                      setState(() {
                        _rating = index + 1.0;
                      });
                    },
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Añade un comentario (opcional)...',
                border: OutlineInputBorder(),
              ),
            ),
            if (_rating < 3.0)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog(context: context, builder: (_) => DisputeDialog(booking: widget.bookings.first));
                    },
                    icon: const Icon(Icons.report_problem, size: 16),
                    label: const Text('Abrir Disputa / Informar de un problema'),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting
              ? null
              : () async {
                  setState(() => _isSubmitting = true);
                  try {
                    final auth = context.read<AuthNotifier>();
                    await context.read<BookingNotifier>().submitReviewForBookings(
                          widget.bookings,
                          _rating,
                          _commentController.text.trim(),
                          auth.currentUserId,
                        );
                    if (context.mounted) {
                      Navigator.pop(context);
                      CustomSnackBar.show(context, message: '¡Reseña enviada! Gracias por tu opinión.', type: SnackBarType.success);
                    }
                  } catch (e) {
                    debugPrint('Error in submitReviewForBookings: $e');
                    setState(() => _isSubmitting = false);
                    if (context.mounted) {
                      CustomSnackBar.show(context, message: 'Error al enviar reseña.', type: SnackBarType.error);
                    }
                  }
                },
          child: _isSubmitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Enviar'),
        ),
      ],
    );
  }
}

