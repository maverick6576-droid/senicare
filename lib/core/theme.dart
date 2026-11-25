import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  /// Permite desactivar las fuentes remotas de Google Fonts en tests headless (`--no-test-assets`).
  static bool useSystemFonts = false;

  // WCAG AA / AAA Compliant Brand Tokens (≥ 5.47:1 on white; ≥ 7.5:1 in Senior Mode)
  static const Color primary = Color(0xFF0F766E); // Teal accesible WCAG AA (5.47:1 con blanco)
  static const Color primarySenior = Color(0xFF115E59); // Teal AAA (7.58:1 con blanco)
  static const Color primaryColor = primary;
  static const Color secondaryColor = Color(0xFF047857); // Esmeralda accesible AA (5.48:1)
  static const Color secondarySenior = Color(0xFF065F46); // Esmeralda AAA (7.68:1)
  static const Color primaryLight = Color(0xFF5EEAD4);
  static const Color primarySurface = Color(0xFFF0FDFA);
  static const Color darkSlate = Color(0xFF0F172A); // 17.85:1 sobre blanco
  static const Color textPrimary = darkSlate;
  static const Color slateMuted = Color(0xFF475569); // 7.58:1 AAA sobre blanco
  static const Color textSecondary = slateMuted;
  static const Color hintText = Color(0xFF64748B); // 4.76:1 AA sobre blanco
  static const Color borderSubtle = Color(0xFFE2E8F0);
  static const Color backgroundNeutral = Color(0xFFF8FAFC);
  static const Color amber = Color(0xFFB45309); // Ámbar accesible sobre fondos claros (5.02:1)

  // Semantic Feedback Tokens (todos ≥ 4.5:1 sobre sus superficies)
  static const Color success = Color(0xFF15803D);
  static const Color successSurface = Color(0xFFF0FDF4);
  static const Color warning = Color(0xFF9A3412);
  static const Color warningSurface = Color(0xFFFFF7ED);
  static const Color danger = Color(0xFFB91C1C);
  static const Color dangerSurface = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF1D4ED8);
  static const Color infoSurface = Color(0xFFEFF6FF);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F172A), Color(0xFF134E4A), Color(0xFF0F766E)],
  );

  static const LinearGradient softTealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF0FDFA), Color(0xFFE6FFFA)],
  );

  static BoxDecoration modernCardDecoration({
    Color? borderColor,
    Color? backgroundColor,
    double radius = 20,
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
    final titleFont = useSystemFonts ? const TextStyle() : GoogleFonts.outfit();
    final bodyFont = useSystemFonts ? const TextStyle() : GoogleFonts.inter();
    final activePrimary = seniorMode ? primarySenior : primary;

    return ThemeData(
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkRipple.splashFactory,
      colorScheme: ColorScheme.fromSeed(
        seedColor: activePrimary,
        primary: activePrimary,
        onPrimary: Colors.white,
        secondary: darkSlate,
        error: danger,
        onError: Colors.white,
        surface: Colors.white,
        onSurface: darkSlate,
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
          backgroundColor: activePrimary,
          foregroundColor: Colors.white,
          minimumSize: Size(0, seniorMode ? 56 : 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: titleFont.copyWith(fontSize: seniorMode ? 19 : 16, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: activePrimary,
          side: BorderSide(color: activePrimary, width: 1.5),
          minimumSize: Size(0, seniorMode ? 56 : 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: titleFont.copyWith(fontSize: seniorMode ? 19 : 16, fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: borderSubtle, width: 1.2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: backgroundNeutral,
        selectedColor: activePrimary.withValues(alpha: 0.14),
        checkmarkColor: activePrimary,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: seniorMode ? 10 : 8),
        side: const BorderSide(color: borderSubtle),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: bodyFont.copyWith(fontSize: seniorMode ? 16 : 13, fontWeight: FontWeight.w600, color: darkSlate),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: seniorMode ? 20 : 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: seniorMode ? slateMuted : hintText, width: seniorMode ? 1.5 : 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: seniorMode ? slateMuted : hintText, width: seniorMode ? 1.5 : 1.2),
        ),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: activePrimary, width: 2.0)),
        labelStyle: bodyFont.copyWith(fontSize: seniorMode ? 17 : 14, color: slateMuted, fontWeight: FontWeight.w500),
        hintStyle: bodyFont.copyWith(color: seniorMode ? slateMuted : hintText),
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
        selectedItemColor: activePrimary,
        unselectedItemColor: slateMuted,
        selectedLabelStyle: titleFont.copyWith(fontSize: seniorMode ? 14 : 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: bodyFont.copyWith(fontSize: seniorMode ? 13 : 12, fontWeight: FontWeight.w600),
        elevation: 8,
      ),
    );
  }
}
