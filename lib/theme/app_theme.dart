import 'package:flutter/material.dart';

/// Defines central design tokens dynamically adaptable for WCAG AAA accessibility,
/// styled with Google Antigravity's modern, airy surface aesthetics while preserving
/// SeniCare's corporate color palette.
class AppTheme {
  // Corporate High-contrast Emerald passing 7:1 contrast ratio against white text
  static const Color primary = Color(0xFF036646);
  static const Color primaryAccent = Color(0xFF058C60);
  static const Color primaryLight = Color(0xFFE6F4EF);
  static const Color surfaceTintMint = Color(0xFFF2FBF7);
  static const Color darkSlate = Color(0xFF0F172A);
  static const Color softSlate = Color(0xFF475569);
  static const Color backgroundNeutral = Color(0xFFF8FAFC);
  // High-contrast Amber 700 (#B45309) passing WCAG AA/AAA visibility against white cards for seniors
  static const Color amber = Color(0xFFB45309);
  static const Color urgentRed = Color(0xFFB91C1C);

  /// Subtle corporate gradient inspired by Google Antigravity headers and hero cards.
  static const LinearGradient antigravityHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF036646), Color(0xFF06845B)],
  );

  /// Soft surface gradient for reassuring informational banners.
  static const LinearGradient antigravitySurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE6F4EF), Color(0xFFF8FAFC)],
  );

  /// Generates the ThemeData reacting to the Senior Mode switch.
  static ThemeData getTheme(bool seniorMode) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: darkSlate,
        surface: backgroundNeutral,
      ),
      scaffoldBackgroundColor: backgroundNeutral,
      // Dynamic typography: Clean, airy, high-legibility hierarchy
      textTheme: TextTheme(
        bodySmall: TextStyle(
          fontSize: seniorMode ? 16 : 13,
          color: softSlate,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: seniorMode ? 19 : 15,
          color: darkSlate,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ),
        titleMedium: TextStyle(
          fontSize: seniorMode ? 22 : 17,
          color: darkSlate,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          fontSize: seniorMode ? 25 : 20,
          color: darkSlate,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        headlineSmall: TextStyle(
          fontSize: seniorMode ? 28 : 23,
          color: darkSlate,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      // Modern pill-inspired buttons with generous touch targets
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: Size(double.infinity, seniorMode ? 64 : 52),
          padding: EdgeInsets.symmetric(
            horizontal: seniorMode ? 24 : 20,
            vertical: seniorMode ? 16 : 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: TextStyle(
            fontSize: seniorMode ? 19 : 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withValues(alpha: 0.35), width: 1.5),
          minimumSize: Size(0, seniorMode ? 64 : 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: TextStyle(
            fontSize: seniorMode ? 18 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primaryLight,
        side: BorderSide(color: primary.withValues(alpha: 0.2)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: primary.withValues(alpha: 0.10), width: 1.2),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}
