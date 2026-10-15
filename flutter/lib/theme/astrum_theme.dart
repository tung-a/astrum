import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'astrum_colors.dart';

class AstrumTheme {
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AstrumColors.gold,
        secondary: AstrumColors.amethyst,
        surface: AstrumColors.deepPurple,
        error: AstrumColors.destructive,
      ),
      scaffoldBackgroundColor: AstrumColors.voidBlack,
    );

    return base.copyWith(
      textTheme: GoogleFonts.outfitTextTheme(base.textTheme).copyWith(
        displaySmall: GoogleFonts.cinzel(
          fontWeight: FontWeight.w600,
          color: AstrumColors.cream,
        ),
        headlineMedium: GoogleFonts.cinzel(
          fontWeight: FontWeight.w600,
          color: AstrumColors.cream,
        ),
        titleLarge: GoogleFonts.cinzel(
          fontWeight: FontWeight.w600,
          color: AstrumColors.cream,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.cinzel(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AstrumColors.cream,
        ),
      ),
      cardTheme: CardThemeData(
        color: AstrumColors.card.withValues(alpha: 0.92),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AstrumColors.card,
        hintStyle: const TextStyle(color: AstrumColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AstrumColors.muted.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AstrumColors.muted.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AstrumColors.gold, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AstrumColors.amethyst,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AstrumColors.deepPurple,
        indicatorColor: AstrumColors.amethyst.withValues(alpha: 0.35),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AstrumColors.gold : AstrumColors.muted,
          );
        }),
      ),
    );
  }
}
