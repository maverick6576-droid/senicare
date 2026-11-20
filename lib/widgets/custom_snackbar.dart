import 'package:flutter/material.dart';
import 'package:senicare/core/theme.dart';

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
        backgroundColor = AppTheme.successSurface;
        icon = Icons.check_circle_rounded;
        iconColor = AppTheme.success;
        break;
      case SnackBarType.error:
        backgroundColor = AppTheme.dangerSurface;
        icon = Icons.error_rounded;
        iconColor = AppTheme.danger;
        break;
      case SnackBarType.warning:
        backgroundColor = AppTheme.warningSurface;
        icon = Icons.warning_rounded;
        iconColor = AppTheme.warning;
        break;
      case SnackBarType.info:
        backgroundColor = AppTheme.infoSurface;
        icon = Icons.info_rounded;
        iconColor = AppTheme.info;
        break;
    }

    final snackBar = SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      duration: duration,
      content: Semantics(
        container: true,
        liveRegion: true,
        label: message,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: iconColor.withValues(alpha: 0.3)),
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
              ExcludeSemantics(
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: AppTheme.darkSlate,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
