import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primary = Color(0xFF0D9488); // Teal más vibrante y premium
  static const Color primaryLight = Color(0xFF5EEAD4);
  static const Color darkSlate = Color(0xFF0F172A); // Slate más profundo
  static const Color backgroundNeutral = Color(0xFFF8FAFC);
  static const Color amber = Color(0xFFF59E0B);
  
  static ThemeData getTheme(bool seniorMode) {
    // Usamos Outfit para títulos (moderno, geométrico) e Inter para cuerpo (legible)
    final titleFont = GoogleFonts.outfit();
    final bodyFont = GoogleFonts.inter();

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: darkSlate,
        background: backgroundNeutral,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: backgroundNeutral,
      textTheme: TextTheme(
        bodyMedium: bodyFont.copyWith(fontSize: seniorMode ? 18 : 14, color: darkSlate, fontWeight: FontWeight.w500),
        titleMedium: titleFont.copyWith(fontSize: seniorMode ? 22 : 16, color: darkSlate, fontWeight: FontWeight.bold),
        titleLarge: titleFont.copyWith(fontSize: seniorMode ? 24 : 18, color: darkSlate, fontWeight: FontWeight.bold),
        headlineSmall: titleFont.copyWith(fontSize: seniorMode ? 28 : 22, color: darkSlate, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, seniorMode ? 64 : 52), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: titleFont.copyWith(fontSize: seniorMode ? 18 : 15, fontWeight: FontWeight.bold),
          elevation: 0, // Botones planos modernos
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          minimumSize: Size(double.infinity, seniorMode ? 64 : 52), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: titleFont.copyWith(fontSize: seniorMode ? 18 : 15, fontWeight: FontWeight.bold),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: primary, width: 1.5)),
        hintStyle: bodyFont.copyWith(color: Colors.grey.shade400),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundNeutral,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: darkSlate),
        titleTextStyle: titleFont.copyWith(fontSize: 20, color: darkSlate, fontWeight: FontWeight.bold),
      ),
    );
  }
}
