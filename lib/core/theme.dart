import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primary = Color(0xFF0D9488); // Teal corporativo vibrante
  static const Color primaryColor = primary;
  static const Color secondaryColor = Color(0xFF059669); // Esmeralda de confirmación
  static const Color primaryLight = Color(0xFF5EEAD4); // Mint luminoso estilo Antigravity
  static const Color primarySurface = Color(0xFFF0FDFA); // Fondo suave Teal
  static const Color darkSlate = Color(0xFF0F172A); // Slate profundo de alto contraste
  static const Color textPrimary = darkSlate;
  static const Color slateMuted = Color(0xFF475569); // Texto secundario legible
  static const Color textSecondary = slateMuted;
  static const Color borderSubtle = Color(0xFFE2E8F0); // Borde fino estructural Antigravity
  static const Color backgroundNeutral = Color(0xFFF8FAFC);
  static const Color amber = Color(0xFFF59E0B);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F172A), Color(0xFF134E4A), Color(0xFF0D9488)],
  );

  static const LinearGradient softTealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF0FDFA), Color(0xFFE6FFFA)],
  );

  static BoxDecoration modernCardDecoration({
    Color? borderColor,
    Color? backgroundColor,
    double radius = 22,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? borderSubtle, width: 1.2),
      boxShadow: [
        BoxShadow(
          color: darkSlate.withValues(alpha: 0.04),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static ThemeData getTheme(bool seniorMode) {
    final titleFont = GoogleFonts.outfit();
    final bodyFont = GoogleFonts.inter();

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: darkSlate,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: backgroundNeutral,
      dividerTheme: const DividerThemeData(
        color: borderSubtle,
        thickness: 1,
      ),
      textTheme: TextTheme(
        bodySmall: bodyFont.copyWith(fontSize: seniorMode ? 15 : 13, color: slateMuted, fontWeight: FontWeight.w500),
        bodyMedium: bodyFont.copyWith(fontSize: seniorMode ? 18 : 15, color: darkSlate, fontWeight: FontWeight.w500, height: 1.45),
        titleMedium: titleFont.copyWith(fontSize: seniorMode ? 22 : 17, color: darkSlate, fontWeight: FontWeight.w700),
        titleLarge: titleFont.copyWith(fontSize: seniorMode ? 25 : 20, color: darkSlate, fontWeight: FontWeight.w800),
        headlineSmall: titleFont.copyWith(fontSize: seniorMode ? 28 : 23, color: darkSlate, fontWeight: FontWeight.w800),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, seniorMode ? 64 : 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: titleFont.copyWith(fontSize: seniorMode ? 19 : 16, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          minimumSize: Size(double.infinity, seniorMode ? 64 : 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: titleFont.copyWith(fontSize: seniorMode ? 19 : 16, fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          side: const BorderSide(color: borderSubtle, width: 1.2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: backgroundNeutral,
        selectedColor: primary.withValues(alpha: 0.14),
        checkmarkColor: primary,
        side: const BorderSide(color: borderSubtle),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: bodyFont.copyWith(fontSize: seniorMode ? 16 : 13, fontWeight: FontWeight.w600, color: darkSlate),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: seniorMode ? 20 : 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: borderSubtle, width: 1.2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: borderSubtle, width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: primary, width: 2.0)),
        labelStyle: bodyFont.copyWith(fontSize: seniorMode ? 17 : 14, color: slateMuted, fontWeight: FontWeight.w500),
        hintStyle: bodyFont.copyWith(color: Colors.grey.shade400),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: darkSlate),
        titleTextStyle: titleFont.copyWith(fontSize: seniorMode ? 22 : 19, color: darkSlate, fontWeight: FontWeight.w800),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: slateMuted,
        selectedLabelStyle: titleFont.copyWith(fontSize: seniorMode ? 14 : 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: bodyFont.copyWith(fontSize: seniorMode ? 13 : 11, fontWeight: FontWeight.w500),
        elevation: 8,
      ),
    );
  }
}
