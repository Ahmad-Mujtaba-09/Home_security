import 'package:flutter/material.dart';

/// Premium colour palette — mirrors the web app's visual identity exactly.
class AppColors {
  AppColors._();

  // ── Dark theme ─────────────────────────
  static const Color darkBg      = Color(0xFF0D0D1A);
  static const Color darkSurface = Color(0xFF161630);
  static const Color darkCard    = Color(0xFF1E1E3F);
  static const Color darkBorder  = Color(0xFF2A2A50);

  // ── Light theme ────────────────────────
  static const Color lightBg      = Color(0xFFF5F6FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard    = Color(0xFFF0F0F8);
  static const Color lightBorder  = Color(0xFFDCDCEA);

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

  // ── Commonly used gradients ────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accentPrimary, accentSecondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient pinkGradient = LinearGradient(
    colors: [accentPink, accentPrimary],
  );

  static const LinearGradient greenGradient = LinearGradient(
    colors: [accentGreen, accentSecondary],
  );
}
