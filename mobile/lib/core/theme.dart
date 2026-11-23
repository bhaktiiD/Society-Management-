import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand + semantic colours. White surfaces, one green, a few status colours.
class AppColors {
  AppColors._();

  // Brand
  static const green = Color(0xFF58CC02); // CTA fill
  static const greenDark = Color(0xFF3A7D00); // small green text (AA contrast)
  static const greenTint = Color(0xFFE9F8D9); // soft green backgrounds
  static const onGreen = Colors.white; // label on green (brand choice; ~2.2:1 contrast)

  // Accent pairs (icon colour + soft background) so different actions get
  // different, friendly colours. Deliberately no blue here.
  static const orange = Color(0xFFC96A00);
  static const orangeTint = Color(0xFFFFEFD9);
  static const purple = Color(0xFF7B4FC9);
  static const purpleTint = Color(0xFFF0E8FB);
  static const rose = Color(0xFFC2415C);
  static const roseTint = Color(0xFFFDE7EC);
  static const teal = Color(0xFF00796B);
  static const tealTint = Color(0xFFDDF3EF);

  // Soft pastel-green gradient for hero cards (top-left -> bottom-right)
  static const heroStart = Color(0xFFDDF5C4);
  static const heroEnd = Color(0xFFF1FBE6);

  // Neutrals
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF6B6B6B);
  static const border = Color(0xFFE5E5E5);
  static const inputBorder = Color(0xFF8F8F8F); // form controls need 3:1
  static const surface = Color(0xFFF7F7F7);

  // Status (kept separate from the brand green)
  static const warning = Color(0xFFFFC800); // fills only (1.6:1 on white)
  static const warningDark = Color(0xFF8A6A00); // icons/text on white (5:1)
  static const warningTint = Color(0xFFFFF6D6);
  static const error = Color(0xFFC5221F); // 5:1 on white and on errorTint
  static const errorTint = Color(0xFFFDE8E6);
  static const info = Color(0xFF1CB0F6); // informational badges only
  static const infoTint = Color(0xFFE3F5FE);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.light(
    primary: AppColors.green,
    onPrimary: AppColors.onGreen,
    primaryContainer: AppColors.greenTint,
    onPrimaryContainer: AppColors.greenDark,
    secondary: AppColors.greenDark,
    surface: Colors.white,
    onSurface: AppColors.ink,
    error: AppColors.error,
    outline: AppColors.border,
  );

  final radius = BorderRadius.circular(16);
  final cardRadius = BorderRadius.circular(20);
  final textTheme = GoogleFonts.nunitoTextTheme(ThemeData.light().textTheme)
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    // Primary call-to-action.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.green,
        foregroundColor: AppColors.onGreen,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.border, width: 2),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.greenDark,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.inputBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.inputBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.green, width: 2),
      ),
    ),
    // White tiles floating on white with a soft shadow (no hard borders).
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 3,
      shadowColor: const Color(0x1A000000),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: cardRadius),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x33000000),
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.greenTint,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.greenDark
              : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.greenDark
              : AppColors.muted,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.green,
      foregroundColor: AppColors.onGreen,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}


/// Soft pastel two-stop backgrounds for icon tiles (light -> slightly deeper).
/// Pair each with a deeper accent icon colour from [AppColors]. No blue.
class AppGradients {
  AppGradients._();

  static const green = [Color(0xFFE9F8DA), Color(0xFFCDEFB0)];
  static const orange = [Color(0xFFFFF2DE), Color(0xFFFFE0B2)];
  static const purple = [Color(0xFFF3ECFD), Color(0xFFE0D2F8)];
  static const teal = [Color(0xFFE2F6F2), Color(0xFFBFE9E1)];
  static const rose = [Color(0xFFFDEBEF), Color(0xFFF9D0DA)];
}
