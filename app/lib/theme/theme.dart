import 'package:flutter/material.dart';
import 'colors.dart';

final chaloTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: ChaloColors.bgApp,
  primaryColor: ChaloColors.primary,
  fontFamily: 'Inter',
  colorScheme: const ColorScheme.dark(
    primary: ChaloColors.primary,
    surface: ChaloColors.bgCard,
    onSurface: ChaloColors.textPrimary,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: ChaloColors.primary,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ChaloColors.textPrimary,
      side: const BorderSide(color: ChaloColors.borderShine, width: 1),
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  ),
  // Every call site in the app just does
  // `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(...)))`
  // with no per-call styling, so this theme-level config is what actually
  // fixes every SnackBar in the app (Agora errors, PTT permission prompts,
  // mock "posted"/"submitted"/"started" confirmations, etc). `floating`
  // (instead of the Material default `fixed`) is also what stops longer
  // messages from being clipped under Android's gesture nav bar — `fixed`
  // pins to the raw screen edge ignoring the bottom safe-area inset,
  // `floating` respects it.
  snackBarTheme: SnackBarThemeData(
    backgroundColor: ChaloColors.bgElevated,
    contentTextStyle: const TextStyle(
      color: ChaloColors.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    actionTextColor: ChaloColors.primary,
    behavior: SnackBarBehavior.floating,
    elevation: 6,
    insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: ChaloColors.borderShine, width: 1),
    ),
  ),
);
