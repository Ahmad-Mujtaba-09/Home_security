import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Dark & light themes that match the web app's visual identity.
class AppTheme {
  AppTheme._();

  static final _baseTextTheme = GoogleFonts.interTextTheme();

  // ─────────────── Dark Theme ───────────────────────────────────────────────
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

  // ─────────────── Light Theme ──────────────────────────────────────────────
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
