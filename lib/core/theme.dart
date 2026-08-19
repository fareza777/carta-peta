import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The app shell palette. Deliberately quiet so the artwork is the only
/// colourful thing on screen.
class Shade {
  static const bg = Color(0xFF0A0A0C);
  static const bgAlt = Color(0xFF101014);
  static const surface = Color(0xFF16161B);
  static const surfaceHi = Color(0xFF1E1E25);
  static const line = Color(0xFF2A2A33);
  static const text = Color(0xFFF3F1EC);
  static const textDim = Color(0xFF9A97A0);
  static const textFaint = Color(0xFF6A6772);
  static const accent = Color(0xFFD8B370);
  static const accentSoft = Color(0xFF3A2F1E);
  static const danger = Color(0xFFE0614D);
}

ThemeData buildTheme() {
  const base = ColorScheme.dark(
    primary: Shade.accent,
    onPrimary: Color(0xFF14100A),
    secondary: Shade.accent,
    surface: Shade.surface,
    onSurface: Shade.text,
    error: Shade.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: Shade.bg,
    fontFamily: 'Inter',
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      displaySmall: TextStyle(color: Shade.text, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(color: Shade.text, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: TextStyle(color: Shade.text, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: Shade.text),
      bodyMedium: TextStyle(color: Shade.textDim, height: 1.35),
      bodySmall: TextStyle(color: Shade.textFaint),
      labelLarge: TextStyle(color: Shade.text, fontWeight: FontWeight.w600),
    ),
    iconTheme: const IconThemeData(color: Shade.text, size: 22),
    dividerTheme: const DividerThemeData(color: Shade.line, thickness: 1, space: 1),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Shade.accent,
      inactiveTrackColor: Shade.line,
      thumbColor: Shade.text,
      overlayColor: Color(0x22D8B370),
      trackHeight: 3,
      showValueIndicator: ShowValueIndicator.never,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Shade.accent : Shade.textFaint),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Shade.accentSoft : Shade.surfaceHi),
      trackOutlineColor: WidgetStateProperty.all(Shade.line),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Shade.surface,
      hintStyle: const TextStyle(color: Shade.textFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Shade.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Shade.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Shade.accent, width: 1.4),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Shade.surfaceHi,
      contentTextStyle: TextStyle(color: Shade.text),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Shade.bgAlt,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
  );
}

const systemOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Shade.bg,
  systemNavigationBarIconBrightness: Brightness.light,
);
