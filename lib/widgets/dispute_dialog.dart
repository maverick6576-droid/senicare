import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/widgets.dart';

class DisputeDialog extends StatefulWidget {
  final Booking booking;

  const DisputeDialog({super.key, required this.booking});

  @override
  State<DisputeDialog> createState() => _DisputeDialogState();
}

class _DisputeDialogState extends State<DisputeDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String? _selectedReason;
  bool _isSubmitting = false;

  final List<String> _reasons = [
    'El cuidador se fue antes de la hora acordada',
    'Comportamiento inapropiado o falta de profesionalidad',
    'No realizó las tareas acordadas',
    'Otros motivos no contemplados'
  ];
  String? _inlineError;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seniorMode = context.watch<ConfigNotifier>().seniorMode;
    final bodyFont = seniorMode ? 15.0 : 13.5;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Informar de un problema',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w800,
                fontSize: seniorMode ? 20 : 18,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tu pago queda retenido y protegido mientras revisamos lo ocurrido. Elige el motivo y qué devolución consideras justa:',
              style: TextStyle(
                fontSize: seniorMode ? 14 : 12.5,
                color: AppTheme.slateMuted,
                height: 1.35,
              ),
            ),
            if (_inlineError != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _inlineError!,
                        style: TextStyle(
                          fontSize: seniorMode ? 13.5 : 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Motivo de la incidencia:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: bodyFont),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _selectedReason,
              hint: const Text('Selecciona una opción'),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _reasons
                  .map(
                    (reason) => DropdownMenuItem(
                      value: reason,
                      child: Text(
                        reason,
                        style: TextStyle(fontSize: bodyFont),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) => setState(() {
                _selectedReason = val;
                _inlineError = null;
              }),
            ),
            const SizedBox(height: 16),
            Text(
              'Comentarios (opcional):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: bodyFont),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Explica brevemente qué ocurrió...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Coste Total Pagado: ${widget.booking.cost.toStringAsFixed(2)} €',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: bodyFont),
            ),
            const SizedBox(height: 14),
            Text(
              'Propuesta de devolución:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: bodyFont),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: Text('25% (${(widget.booking.cost * 0.25).toStringAsFixed(1)}€)'),
                  onPressed: () {
                    setState(() {
                      _amountController.text = (widget.booking.cost * 0.25).toStringAsFixed(2);
                      _inlineError = null;
                    });
                  },
                ),
                ActionChip(
                  label: Text('50% (${(widget.booking.cost * 0.50).toStringAsFixed(1)}€)'),
                  onPressed: () {
                    setState(() {
                      _amountController.text = (widget.booking.cost * 0.50).toStringAsFixed(2);
                      _inlineError = null;
                    });
                  },
                ),
                ActionChip(
                  label: Text('100% (${widget.booking.cost.toStringAsFixed(1)}€)'),
                  onPressed: () {
                    setState(() {
                      _amountController.text = widget.booking.cost.toStringAsFixed(2);
                      _inlineError = null;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountController,
              onChanged: (_) {
                if (_inlineError != null) {
                  setState(() => _inlineError = null);
                }
              },
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Importe exacto (€)',
                hintText: 'Ej. 15.50',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            foregroundColor: Colors.white,
          ),
          onPressed: _isSubmitting
              ? null
              : () async {
                  if (_selectedReason == null) {
                    setState(() {
                      _inlineError = 'Por favor, selecciona un motivo antes de enviar.';
                    });
                    return;
                  }

                  final amountText = _amountController.text.replaceAll(',', '.');
                  final amount = double.tryParse(amountText);

                  if (amount == null || amount <= 0 || amount > widget.booking.cost) {
                    setState(() {
                      _inlineError =
                          'Introduce un importe mayor que 0 € y que no supere ${widget.booking.cost.toStringAsFixed(2)} €.';
                    });
                    return;
                  }

                  setState(() {
                    _isSubmitting = true;
                    _inlineError = null;
                  });
                  try {
                    await context.read<BookingNotifier>().openDispute(
                          widget.booking.id,
                          amount,
                          _selectedReason!,
                          _descriptionController.text.trim(),
                        );
                    if (context.mounted) {
                      Navigator.pop(context);
                      CustomSnackBar.show(
                        context,
                        message: 'Incidencia enviada. El cuidador tiene 24 horas para responder.',
                        type: SnackBarType.success,
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _isSubmitting = false;
                        _inlineError = 'Error al enviar la incidencia: $e';
                      });
                    }
                  }
                },
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Enviar Incidencia'),
        ),
      ],
    );
  }
}
