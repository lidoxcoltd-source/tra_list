import 'package:flutter/material.dart';

class MjasiColors {
  static const primaryNavy = Color(0xFF10233F);
  static const primaryBlue = Color(0xFF2457D6);
  static const secondaryBlue = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFFEFF4FF);
  static const background = Color(0xFFF5F7FB);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF17263D);
  static const textSecondary = Color(0xFF68778D);
  static const success = Color(0xFF138365);
  static const warning = Color(0xFFCB7A22);
  static const error = Color(0xFFC64F5D);
  static const border = Color(0xFFE4E9F1);
  static const successBackground = Color(0xFFECF8F3);
  static const errorBackground = Color(0xFFFCF0F1);
  static const warningBackground = Color(0xFFFFF7EB);
}

class MjasiSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class MjasiRadius {
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

class MjasiTheme {
  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: MjasiColors.primaryBlue,
          brightness: Brightness.light,
        ).copyWith(
          primary: MjasiColors.primaryBlue,
          secondary: MjasiColors.secondaryBlue,
          surface: MjasiColors.surface,
          error: MjasiColors.error,
        );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: MjasiColors.background,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: MjasiColors.surface,
        foregroundColor: MjasiColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          color: MjasiColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
      cardTheme: CardThemeData(
        color: MjasiColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.md),
          side: const BorderSide(color: MjasiColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.md),
        ),
        backgroundColor: MjasiColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MjasiColors.primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MjasiRadius.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MjasiColors.primaryBlue,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: MjasiColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MjasiRadius.sm),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MjasiColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
          borderSide: const BorderSide(color: MjasiColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
          borderSide: const BorderSide(color: MjasiColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
          borderSide: const BorderSide(color: Color(0xFF035BD6), width: 1.5),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(MjasiRadius.sm),
      ),
    );
  }
}
