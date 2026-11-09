import 'package:flutter/material.dart';

/// Colours from the TripKhata design canvas.
class AppColors {
  static const primary = Color(0xFF0E5E6F);
  static const primaryDark = Color(0xFF0A4652);
  static const primarySoft = Color(0xFFDCEBEE);
  static const primaryTint = Color(0xFFEEF6F7);
  static const yellow = Color(0xFFF2B33D);
  static const yellowSoft = Color(0xFFFDF1D8);
  static const text = Color(0xFF15181C);
  static const textMuted = Color(0xFF5B636D);
  static const line = Color(0xFFE4E7EB);
  static const lineSoft = Color(0xFFEEF0F2);
  static const border = Color(0xFFD5D9DE);
  static const background = Color(0xFFF5F6F7);
  static const owe = Color(0xFFB4470F);
  static const oweSoft = Color(0xFFFDE8E1);

  /// Avatar colours, picked by member.colorIndex.
  static const people = [
    primary,
    Color(0xFFA15C00),
    Color(0xFF2F55B5),
    Color(0xFF7A4BB0),
    owe,
    Color(0xFF4D555E),
  ];
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Figtree',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.yellow,
        surface: Colors.white,
        error: AppColors.owe,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );
    final text = base.textTheme.apply(
      fontFamily: 'Figtree',
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: AppColors.text,
        elevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.lineSoft, space: 1, thickness: 1),
    );
  }
}
