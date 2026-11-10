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

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Abrir Disputa', style: TextStyle(color: Colors.orange)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Al abrir una disputa, el pago quedará retenido. Por favor, selecciona el motivo y propón un reembolso justo.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text('Motivo de la incidencia:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _selectedReason,
              hint: const Text('Selecciona una opción'),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _reasons.map((reason) => DropdownMenuItem(value: reason, child: Text(reason, style: const TextStyle(fontSize: 14)))).toList(),
              onChanged: (val) => setState(() => _selectedReason = val),
            ),
            const SizedBox(height: 16),
            const Text('Comentarios (opcional):', style: TextStyle(fontWeight: FontWeight.bold)),
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
            Text('Coste Total Pagado: ${widget.booking.cost.toStringAsFixed(2)} €', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            const Text('Propuesta de reembolso:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: Text('25% (${(widget.booking.cost * 0.25).toStringAsFixed(1)}€)'),
                  onPressed: () {
                    _amountController.text = (widget.booking.cost * 0.25).toStringAsFixed(2);
                  },
                ),
                ActionChip(
                  label: Text('50% (${(widget.booking.cost * 0.50).toStringAsFixed(1)}€)'),
                  onPressed: () {
                    _amountController.text = (widget.booking.cost * 0.50).toStringAsFixed(2);
                  },
                ),
                ActionChip(
                  label: Text('100% (${widget.booking.cost.toStringAsFixed(1)}€)'),
                  onPressed: () {
                    _amountController.text = widget.booking.cost.toStringAsFixed(2);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountController,
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
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          onPressed: _isSubmitting
              ? null
              : () async {
                  if (_selectedReason == null) {
                    CustomSnackBar.show(context, message: 'Por favor, selecciona un motivo.', type: SnackBarType.error);
                    return;
                  }
                  
                  final amountText = _amountController.text.replaceAll(',', '.');
                  final amount = double.tryParse(amountText);
                  
                  if (amount == null || amount <= 0 || amount > widget.booking.cost) {
                    CustomSnackBar.show(context, message: 'Por favor, introduce una cantidad mayor que 0 € y que no supere el coste total.', type: SnackBarType.error);
                    return;
                  }
                  
                  setState(() => _isSubmitting = true);
                  try {
                    await context.read<BookingNotifier>().openDispute(
                      widget.booking.id, 
                      amount,
                      _selectedReason!,
                      _descriptionController.text.trim()
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      CustomSnackBar.show(context, message: 'Disputa abierta. El cuidador tiene 24 horas para responder.', type: SnackBarType.success);
                    }
                  } catch (e) {
                    setState(() => _isSubmitting = false);
                    if (context.mounted) {
                      CustomSnackBar.show(context, message: 'Error al abrir la disputa: $e', type: SnackBarType.error);
                    }
                  }
                },
          child: _isSubmitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Enviar Propuesta'),
        ),
      ],
    );
  }
}
