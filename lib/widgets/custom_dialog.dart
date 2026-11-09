import 'package:flutter/material.dart';

class CustomDialog {
  static Future<void> showError(
    BuildContext context, {
    String title = 'Error',
    required String message,
    String buttonText = 'Aceptar',
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.3),
        ),
        actionsAlignment: MainAxisAlignment.center,
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.only(top: 16, bottom: 8),
        actions: [
          const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> showSuccess(
    BuildContext context, {
    String title = 'Éxito',
    required String message,
    String buttonText = 'Continuar',
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Column(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.3),
        ),
        actionsAlignment: MainAxisAlignment.center,
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.only(top: 16, bottom: 8),
        actions: [
          const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<bool?> showConfirmation(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Aceptar',
    String cancelText = 'Cancelar',
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.3),
        ),
        actionsAlignment: MainAxisAlignment.center,
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.only(top: 16, bottom: 8),
        actions: [
          const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(10))),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    cancelText,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 48, color: const Color(0xFFEEEEEE)),
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomRight: Radius.circular(10))),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    confirmText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDestructive ? Colors.red : Colors.blueAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
