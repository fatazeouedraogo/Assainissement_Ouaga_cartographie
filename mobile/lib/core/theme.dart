import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Pal {
  static const primary = Color(0xFF10B981);
  static const primaryDeep = Color(0xFF059669);
  static const primaryFixed = Color(0xFFD1FAE5);
  static const onPrimaryFixed = Color(0xFF065F46);
  static const secondary = Color(0xFF2563EB);
  static const secondaryFixed = Color(0xFFDBEAFE);
  static const tertiary = Color(0xFFF59E0B);
  static const tertiaryFixed = Color(0xFFFEF3C7);
  static const tertiaryDeep = Color(0xFF92400E);
  static const error = Color(0xFFEF4444);
  static const errorSoft = Color(0xFFFEE2E2);
  static const surface = Color(0xFFF8FAFC);
  static const container = Color(0xFFF1F5F9);
  static const line = Color(0xFFE2E8F0);
  static const ink = Color(0xFF0F172A);
  static const inkSoft = Color(0xFF475569);
  static const outline = Color(0xFF94A3B8);
}

TextStyle head(double size, {FontWeight w = FontWeight.w800, Color c = Pal.ink, double? h}) =>
    GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: w,
      color: c,
      height: h,
      letterSpacing: -0.01 * size,
    );

TextStyle body(double size, {FontWeight w = FontWeight.w400, Color c = Pal.ink, double? h}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Pal.primary, brightness: Brightness.light).copyWith(
    primary: Pal.primary,
    onPrimary: Colors.white,
    secondary: Pal.secondary,
    tertiary: Pal.tertiary,
    error: Pal.error,
    surface: Pal.surface,
    onSurface: Pal.ink,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Pal.surface,
    textTheme: GoogleFonts.interTextTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: Pal.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Pal.ink,
      titleTextStyle: head(18),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(Pal.line),
      enabledBorder: border(Pal.line),
      focusedBorder: border(Pal.primary, 1.8),
      labelStyle: body(14, c: Pal.inkSoft),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pal.ink,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Pal.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Pal.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: body(13, c: Colors.white),
    ),
    dividerTheme: const DividerThemeData(color: Pal.line, thickness: 1, space: 1),
  );
}
