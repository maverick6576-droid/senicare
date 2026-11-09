import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';

class StatusBadge extends StatelessWidget {
  final BookingStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case BookingStatus.pendingPayment:
        bg = Colors.grey.shade200; fg = Colors.grey.shade800; text = 'Pago en proc...'; break;
      case BookingStatus.pending:
        bg = Colors.orange.shade50; fg = Colors.orange.shade800; text = 'Pendiente'; break;
      case BookingStatus.confirmed:
        bg = Colors.blue.shade50; fg = Colors.blue.shade800; text = 'Confirmado'; break;
      case BookingStatus.completed:
        bg = Colors.green.shade50; fg = Colors.green.shade800; text = 'Completado'; break;
      case BookingStatus.cancelled:
        bg = Colors.red.shade50; fg = Colors.red.shade800; text = 'Cancelado'; break;
      case BookingStatus.cancelledLate:
        bg = Colors.purple.shade50; fg = Colors.purple.shade800; text = 'Canc. Tardía'; break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}
