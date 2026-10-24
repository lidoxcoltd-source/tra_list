import 'package:flutter/material.dart';

class MjasiColors {
  static const primaryNavy = Color.fromARGB(255, 2, 13, 112);
  static const primaryBlue = Color.fromARGB(255, 15, 102, 223);
  static const secondaryBlue = Color.fromARGB(255, 9, 103, 255);
  static const lightBlue = Color(0xFFEAF3FF);
  static const background = Color(0xFFF5F8FC);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF14243A);
  static const textSecondary = Color(0xFF718096);
  static const success = Color(0xFF09993E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFC71414);
  static const border = Color(0xFFE2E8F0);
  static const successBackground = Color(0xFFECFDF5);
  static const errorBackground = Color(0xFFFEF2F2);
  static const warningBackground = Color(0xFFFFFBEB);
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
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const pill = 999.0;
}

class MjasiTheme {
  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF0455C7),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF0459CF),
          secondary: const Color(0xFF0464FF),
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
