// نظام الألوان والتصميم — مستوحى من نظام تصميم ui-ux-pro-max.
//
// لوحة ألوان داكنة فاخرة مناسبة لتطبيقات الصوت والقرآن:
//  - Primary:   #04241F (بنفسجي داكن عميق)
//  - Accent:    #D9AA63 (برتقالي دافئ للـ CTA)
//  - Background:#0F0F23 (خلفية ليلية)
//  - Surface:   #27273B (بطاقات/أسطح)
//
// Color system — derived from the ui-ux-pro-max design system.
// Dark luxury palette suited for audio/Quran apps.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // الألوان الأساسية / Brand
  static const Color primary = Color(0xFF04241F);
  static const Color primaryLight = Color(0xFF113A38);
  static const Color accent = Color(0xFFD9AA63);
  static const Color accentLight = Color(0xFFFB923C);

  // الخلفيات والأسطح / Backgrounds & surfaces
  static const Color background = Color(0xFF04241F);
  static const Color surface = Color(0xFF113A38);
  static const Color surfaceLight = Color(0xFF1C4A42);
  static const Color muted = Color(0xFF1C4A42);

  // النصوص / Text
  static const Color textPrimary = Color(0xFFFDFAF7);
  static const Color textSecondary = Color(0xFFFDFAF7);
  static const Color textMuted = Color(0xFFFDFAF7);

  // الحالات / States
  static const Color border = Color(0xFF1C4A42);
  static const Color success = Color(0xFF22C55E);
  static const Color destructive = Color(0xFFEF4444);

  /// ظل ناعم للأسطح البارزة (تأثير neumorphism خفيف).
  /// Soft shadow for elevated surfaces (subtle neumorphism).
  static List<BoxShadow> softGlow({Color? color, double blur = 20}) => [
        BoxShadow(
          color: (color ?? accent).withValues(alpha: 0.15),
          blurRadius: blur,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      ];
}

/// ثيم التطبيق الكامل / Full app theme.
ThemeData appTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.primaryLight,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.destructive,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      margin: EdgeInsets.zero,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        backgroundColor: AppColors.surfaceLight,
        padding: const EdgeInsets.all(12),
        minimumSize: const Size(48, 48), // touch target ≥48dp
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle: const TextStyle(color: AppColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.surfaceLight, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.surfaceLight,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceLight,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}
