import 'package:flutter/material.dart';
import 'package:senicare/core/theme.dart';
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
        bg = const Color(0xFFF1F5F9);
        fg = AppTheme.darkSlate;
        text = 'Pago en proceso';
        break;
      case BookingStatus.pending:
        bg = AppTheme.warningSurface;
        fg = AppTheme.warning;
        text = 'Pendiente';
        break;
      case BookingStatus.confirmed:
        bg = AppTheme.infoSurface;
        fg = AppTheme.info;
        text = 'Confirmado';
        break;
      case BookingStatus.completed:
        bg = AppTheme.successSurface;
        fg = AppTheme.success;
        text = 'Completado';
        break;
      case BookingStatus.cancelled:
        bg = AppTheme.dangerSurface;
        fg = AppTheme.danger;
        text = 'Cancelado';
        break;
      case BookingStatus.cancelledLate:
        bg = const Color(0xFFFAF5FF);
        fg = const Color(0xFF6B21A8);
        text = 'Cancelación tardía';
        break;
    }

    return Semantics(
      label: 'Estado: $text',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fg.withValues(alpha: 0.25)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
