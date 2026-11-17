import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Pal {
  static const ground = Color(0xFFE6E9E1);
  static const surface = Color(0xFFF5F6F1);
  static const ink = Color(0xFF17262B);
  static const inkSoft = Color(0xFF51636A);
  static const line = Color(0xFFCBD1C6);
  static const signal = Color(0xFFF2B705);
  static const dump = Color(0xFFC8372D);
  static const pending = Color(0xFFE08A1E);
  static const planned = Color(0xFF2F6DB5);
  static const cleaned = Color(0xFF2E7D5B);
  static const point = Color(0xFF0E7C66);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Pal.ink,
      primary: Pal.ink,
      onPrimary: Pal.surface,
      secondary: Pal.signal,
      onSecondary: Pal.ink,
      surface: Pal.surface,
      error: Pal.dump,
    ),
    scaffoldBackgroundColor: Pal.ground,
  );
  final body = GoogleFonts.hankenGroteskTextTheme(base.textTheme).apply(bodyColor: Pal.ink, displayColor: Pal.ink);
  final head = GoogleFonts.bricolageGrotesque;
  return base.copyWith(
    textTheme: body.copyWith(
      headlineMedium: head(fontSize: 28, fontWeight: FontWeight.w800, height: 1.05, color: Pal.ink),
      titleLarge: head(fontSize: 21, fontWeight: FontWeight.w700, color: Pal.ink),
      titleMedium: head(fontSize: 16, fontWeight: FontWeight.w700, color: Pal.ink),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Pal.ground,
      foregroundColor: Pal.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: head(fontSize: 20, fontWeight: FontWeight.w800, color: Pal.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.ink,
        foregroundColor: Pal.surface,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: body.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pal.ink,
        side: const BorderSide(color: Pal.ink, width: 1.4),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Pal.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Pal.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Pal.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Pal.ink, width: 1.6)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Pal.surface,
      indicatorColor: Pal.signal,
      height: 66,
      labelTextStyle: WidgetStatePropertyAll(body.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
    ),
    dividerTheme: const DividerThemeData(color: Pal.line, thickness: 1, space: 1),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: Pal.ink,
      inactiveTrackColor: Pal.line,
      thumbColor: Pal.ink,
      overlayColor: Pal.signal.withValues(alpha: 0.3),
      trackHeight: 3,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Pal.surface,
      selectedColor: Pal.ink,
      side: const BorderSide(color: Pal.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      labelStyle: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class Plate extends StatelessWidget {
  const Plate({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Pal.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Pal.line),
        ),
        child: child,
      );
}
