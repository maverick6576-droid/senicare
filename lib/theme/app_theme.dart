import 'package:flutter/material.dart';

/// Defines central design tokens dynamically adaptable for WCAG AAA accessibility.
class AppTheme {
  // High-contrast emerald passing 7:1 contrast ratio against white text
  static const Color primary = Color(0xFF036646);
  static const Color primaryLight = Color(0xFFE6F4EF);
  static const Color darkSlate = Color(0xFF0F172A);
  static const Color backgroundNeutral = Color(0xFFF8FAFC);
  static const Color amber = Colors.amber;
  static const Color urgentRed = Color(0xFFB91C1C);

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
      // Dynamic typography: Scales up significantly if seniorMode is true (WCAG AAA)
      textTheme: TextTheme(
        bodySmall: TextStyle(
          fontSize: seniorMode ? 16 : 12,
          color: darkSlate,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(
          fontSize: seniorMode ? 19 : 14,
          color: darkSlate,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        titleMedium: TextStyle(
          fontSize: seniorMode ? 22 : 16,
          color: darkSlate,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: TextStyle(
          fontSize: seniorMode ? 25 : 18,
          color: darkSlate,
          fontWeight: FontWeight.bold,
        ),
        headlineSmall: TextStyle(
          fontSize: seniorMode ? 28 : 22,
          color: darkSlate,
          fontWeight: FontWeight.bold,
        ),
      ),
      // Dynamic touch targets for buttons (minimum 64dp height in Senior Mode)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, seniorMode ? 64 : 48),
          padding: EdgeInsets.symmetric(
            horizontal: seniorMode ? 24 : 16,
            vertical: seniorMode ? 16 : 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: TextStyle(
            fontSize: seniorMode ? 19 : 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, seniorMode ? 64 : 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: TextStyle(
            fontSize: seniorMode ? 18 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }
}
