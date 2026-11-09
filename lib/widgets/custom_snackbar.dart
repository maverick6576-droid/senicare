import 'package:flutter/material.dart';

enum SnackBarType { success, error, warning, info }

class CustomSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    SnackBarType type = SnackBarType.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    Color backgroundColor;
    IconData icon;
    Color iconColor;

    switch (type) {
      case SnackBarType.success:
        backgroundColor = const Color(0xFFE8F5E9); // Light green
        icon = Icons.check_circle_rounded;
        iconColor = const Color(0xFF2E7D32);
        break;
      case SnackBarType.error:
        backgroundColor = const Color(0xFFFFEBEE); // Light red
        icon = Icons.error_rounded;
        iconColor = const Color(0xFFC62828);
        break;
      case SnackBarType.warning:
        backgroundColor = const Color(0xFFFFF8E1); // Light orange
        icon = Icons.warning_rounded;
        iconColor = const Color(0xFFF57F17);
        break;
      case SnackBarType.info:
      default:
        backgroundColor = const Color(0xFFE3F2FD); // Light blue
        icon = Icons.info_rounded;
        iconColor = const Color(0xFF1565C0);
        break;
    }

    final snackBar = SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      duration: duration,
      content: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
