import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Dark Surfaces ────────────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0B0F14);
  static const Color surfaceDark = Color(0xFF151B23);
  static const Color surfaceElevatedDark = Color(0xFF1A212B);
  static const Color surfaceHighlightDark = Color(0xFF222B38);

  // ── Light Surfaces ───────────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF7F9FC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFF1F5F9);
  static const Color surfaceHighlightLight = Color(0xFFE2E8F0);

  // ── Primaries (Emerald & Mint) ───────────────────────────────────────────
  static const Color primaryLight = Color(0xFF00A982);       // Light mode emerald
  static const Color primaryDark = Color(0xFF00D4A8);        // Dark mode mint
  static const Color primaryLightSurface = Color(0xFFDDF7EF);
  static const Color primaryDarkSurface = Color(0xFF103B32);

  // Backwards compatible aliases
  static const Color background = backgroundDark;
  static const Color surface = surfaceDark;
  static const Color surfaceElevated = surfaceElevatedDark;
  static const Color surfaceHighlight = surfaceHighlightDark;
  static const Color primary = primaryLight;

  // ── Accents ──────────────────────────────────────────────────────────────
  static const Color accentLight = Color(0xFF3478F6);        // Light mode blue
  static const Color accentDark = Color(0xFF4DA3FF);         // Dark mode blue
  static const Color accent = accentLight;

  // ── Semantics ────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF00D4A8);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFF5B942);
  static const Color error = Color(0xFFEF4444);
  static const Color errorDark = Color(0xFFFF6B6B);
  static const Color info = Color(0xFF3478F6);

  // ── Text Tokens ──────────────────────────────────────────────────────────
  static const Color textPrimaryDark = Color(0xFFF5F7FA);
  static const Color textSecondaryDark = Color(0xFF98A2B3);
  static const Color textTertiaryDark = Color(0xFF667085);
  static const Color textDisabledDark = Color(0xFF475467);

  static const Color textPrimaryLight = Color(0xFF111827);
  static const Color textSecondaryLight = Color(0xFF667085);
  static const Color textTertiaryLight = Color(0xFF98A2B3);

  // Backwards compatible aliases
  static const Color textPrimary = textPrimaryDark;
  static const Color textSecondary = textSecondaryDark;
  static const Color textTertiary = textTertiaryDark;
  static const Color textDisabled = textDisabledDark;

  // ── Borders ──────────────────────────────────────────────────────────────
  static const Color borderDark = Color(0xFF252C36);
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color borderSubtleDark = Color(0xFF1A212B);
  static const Color borderAccent = Color(0x4000D4A8);

  // Backwards compatible aliases
  static const Color border = borderDark;
  static const Color borderSubtle = borderSubtleDark;

  // ── Gradients ────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00A982), Color(0xFF3478F6)],
  );

  static const LinearGradient surfaceGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF151B23), Color(0xFF0B0F14)],
  );

  static const LinearGradient surfaceGradient = surfaceGradientDark;

  // ── Dynamic Context-Aware Resolvers ──────────────────────────────────────
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color getBg(BuildContext context) =>
      isDark(context) ? backgroundDark : backgroundLight;

  static Color getCard(BuildContext context) =>
      isDark(context) ? surfaceDark : surfaceLight;

  static Color getSurfaceElevated(BuildContext context) =>
      isDark(context) ? surfaceElevatedDark : surfaceElevatedLight;

  static Color getText(BuildContext context) =>
      isDark(context) ? textPrimaryDark : textPrimaryLight;

  static Color getSubtext(BuildContext context) =>
      isDark(context) ? textSecondaryDark : textSecondaryLight;

  static Color getBorder(BuildContext context) =>
      isDark(context) ? borderDark : borderLight;

  static Color getPrimary(BuildContext context) =>
      isDark(context) ? primaryDark : primaryLight;

  static Color getAccent(BuildContext context) =>
      isDark(context) ? accentDark : accentLight;

  static Color getError(BuildContext context) =>
      isDark(context) ? errorDark : error;

  static Color getWarning(BuildContext context) =>
      isDark(context) ? warningDark : warning;
}

// Full backward-compatible alias for existing codebase
typedef MeshColors = AppColors;
