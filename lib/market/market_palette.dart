import 'package:flutter/material.dart';

abstract final class MarketPalette {
  static const canvas = Color(0xFF070D17);
  static const surface = Color(0xFF111B2A);
  static const surfaceRaised = Color(0xFF18253A);
  static const border = Color(0xFF29394F);
  static const text = Color(0xFFF2F6FC);
  static const textMuted = Color(0xFFA8B6C8);
  static const blue = Color(0xFF5BA2FF);
  static const blueSoft = Color(0xFF1C385A);
  static const navy = Color(0xFF0D2A4A);
  static const topBar = Color(0xFF173C5B);
  static const red = Color(0xFFFF6B7A);
  static const mint = Color(0xFF55D6BE);
  static const blackActionOverlay = Color(0x73000000);
  static const actionCornerRadius = 8.0;

  static ButtonStyle get statusActionButtonStyle => FilledButton.styleFrom(
    backgroundColor: blackActionOverlay,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(actionCornerRadius),
    ),
  );

  static ButtonStyle get feedModeButtonStyle => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.selected)
          ? const Color(0x99000000)
          : blackActionOverlay;
    }),
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    side: const WidgetStatePropertyAll(BorderSide.none),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(actionCornerRadius),
      ),
    ),
  );

  static ThemeData darkTheme(ThemeData base) => base.copyWith(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    dividerColor: border,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: topBar,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: text),
      actionsIconTheme: const IconThemeData(color: text),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    colorScheme: const ColorScheme.dark(
      primary: blue,
      secondary: mint,
      surface: surface,
      error: red,
      onPrimary: Colors.white,
      onSecondary: canvas,
      onSurface: text,
      onError: Colors.white,
    ),
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        color: text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(color: textMuted, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: surface,
      labelStyle: const TextStyle(color: textMuted),
      hintStyle: const TextStyle(color: textMuted),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: blue, width: 1.5),
      ),
    ),
  );
}
