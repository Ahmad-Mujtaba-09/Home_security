import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium colour palette used throughout the app.
class AppColors {
  AppColors._();

  // ── Dark theme ─────────────────────────
  static const Color darkBg        = Color(0xFF0D0D1A);
  static const Color darkSurface   = Color(0xFF161630);
  static const Color darkCard      = Color(0xFF1E1E3F);
  static const Color darkBorder    = Color(0xFF2A2A50);

  // ── Light theme ────────────────────────
  static const Color lightBg       = Color(0xFFF5F6FA);
  static const Color lightSurface  = Color(0xFFFFFFFF);
  static const Color lightCard     = Color(0xFFF0F0F8);
  static const Color lightBorder   = Color(0xFFDCDCEA);

  // ── Accent gradients ───────────────────
  static const Color accentPrimary   = Color(0xFF6C63FF);
  static const Color accentSecondary = Color(0xFF00D2FF);
  static const Color accentPink      = Color(0xFFFF6B9D);
  static const Color accentGreen     = Color(0xFF00E676);
  static const Color accentOrange    = Color(0xFFFF9100);

  // ── Semantic ───────────────────────────
  static const Color danger  = Color(0xFFFF3D5A);
  static const Color warning = Color(0xFFFFC107);
  static const Color success = Color(0xFF00E676);
  static const Color info    = Color(0xFF29B6F6);
}

class AppTheme {
  AppTheme._();

  static final _baseTextTheme = GoogleFonts.interTextTheme();

  // ─────────────── Dark Theme ─────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkBg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accentPrimary,
          secondary: AppColors.accentSecondary,
          surface: AppColors.darkSurface,
          error: AppColors.danger,
        ),
        textTheme: _baseTextTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.darkBorder, width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentPrimary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.accentPrimary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkSurface,
          selectedItemColor: AppColors.accentPrimary,
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
      );

  // ─────────────── Light Theme ────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.lightBg,
        colorScheme: const ColorScheme.light(
          primary: AppColors.accentPrimary,
          secondary: AppColors.accentSecondary,
          surface: AppColors.lightSurface,
          error: AppColors.danger,
        ),
        textTheme: _baseTextTheme.apply(
          bodyColor: const Color(0xFF1A1A2E),
          displayColor: const Color(0xFF1A1A2E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
          iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
        ),
        cardTheme: CardThemeData(
          color: AppColors.lightCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.lightBorder, width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentPrimary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.lightCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.accentPrimary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.35)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.lightSurface,
          selectedItemColor: AppColors.accentPrimary,
          unselectedItemColor: Colors.black38,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
      );
}
