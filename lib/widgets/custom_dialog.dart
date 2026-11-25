import 'package:flutter/material.dart';
import 'package:senicare/core/theme.dart';

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
        content: SingleChildScrollView(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppTheme.darkSlate, height: 1.35),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.only(top: 16, bottom: 8),
        actions: [
          const Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.info,
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
            const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 48),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppTheme.darkSlate, height: 1.35),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.only(top: 16, bottom: 8),
        actions: [
          const Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.info,
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
      builder: (context) {
        final isLargeText = MediaQuery.textScalerOf(context).scale(1) > 1.25;
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppTheme.darkSlate, height: 1.35),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          actionsPadding: const EdgeInsets.only(top: 16, bottom: 8),
          actions: [
            const Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
            if (isLargeText)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        confirmText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDestructive ? AppTheme.danger : AppTheme.info,
                        ),
                      ),
                    ),
                    const Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        cancelText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(10)),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          cancelText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, thickness: 1, color: AppTheme.borderSubtle),
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomRight: Radius.circular(10)),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(
                          confirmText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDestructive ? AppTheme.danger : AppTheme.info,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
