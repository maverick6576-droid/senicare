import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/widgets.dart';

class ReportDialog extends StatefulWidget {
  final Booking booking;

  const ReportDialog({super.key, required this.booking});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String _selectedReason = 'No se presentó';
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _reasons = [
    'No se presentó',
    'Llegó muy tarde',
    'Comportamiento inadecuado',
    'No cumplió con las tareas',
    'Otro'
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Reportar Incidente', style: TextStyle(color: Colors.red)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Esta denuncia es estrictamente confidencial y se enviará directamente al equipo de administración para su investigación.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            const Text('Motivo principal:'),
            DropdownButtonFormField<String>(
              initialValue: _selectedReason,
              items: _reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedReason = val);
              },
            ),
            const SizedBox(height: 16),
            const Text('Descripción detallada:'),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Explica qué ha sucedido de forma detallada...',
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
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: _isSubmitting
              ? null
              : () async {
                  if (_descriptionController.text.trim().isEmpty) {
                    CustomSnackBar.show(context, message: 'Por favor, proporciona una descripción.', type: SnackBarType.info);
                    return;
                  }
                  setState(() => _isSubmitting = true);
                  try {
                    final auth = context.read<AuthNotifier>();
                    await context.read<BookingNotifier>().submitReport(
                          widget.booking.caregiverId,
                          widget.booking.id,
                          _selectedReason,
                          _descriptionController.text.trim(),
                          auth.currentUserId,
                        );
                    if (context.mounted) {
                      Navigator.pop(context);
                      CustomSnackBar.show(context, message: 'Incidente reportado con éxito. El equipo se pondrá en contacto contigo pronto.', type: SnackBarType.error);
                    }
                  } catch (e) {
                    setState(() => _isSubmitting = false);
                    if (context.mounted) {
                      CustomSnackBar.show(context, message: 'Error al enviar el reporte.', type: SnackBarType.error);
                    }
                  }
                },
          child: _isSubmitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Enviar Reporte'),
        ),
      ],
    );
  }
}

