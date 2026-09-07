import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  AppTypography._();

  static TextTheme uiTextTheme(TextTheme base, Color color) {
    return GoogleFonts.sourceSans3TextTheme(
      base,
    ).apply(bodyColor: color, displayColor: color);
  }

  static TextStyle kanji({required Color color, double size = 112}) {
    return GoogleFonts.notoSerifJp(
      fontSize: size,
      fontWeight: FontWeight.w500,
      height: 1.05,
      color: color,
    );
  }

  static TextStyle keyword({required Color color}) {
    return GoogleFonts.sourceSans3(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.6,
      color: color,
    );
  }
}
