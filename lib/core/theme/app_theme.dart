import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/kanji_status.dart';
import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.paper,
    );
    return _build(
      base: base,
      background: AppColors.paper,
      surface: AppColors.paper,
      text: AppColors.charcoal,
      muted: AppColors.muted,
      primary: AppColors.indigo,
      onPrimary: Colors.white,
      hairline: AppColors.hairline,
      overlay: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.paper,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkScaffold,
    );
    return _build(
      base: base,
      background: AppColors.darkScaffold,
      surface: AppColors.darkSurface,
      text: AppColors.darkText,
      muted: AppColors.darkMuted,
      primary: AppColors.darkIndigo,
      onPrimary: AppColors.darkScaffold,
      hairline: AppColors.darkHairline,
      overlay: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.darkScaffold,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  static ThemeData _build({
    required ThemeData base,
    required Color background,
    required Color surface,
    required Color text,
    required Color muted,
    required Color primary,
    required Color onPrimary,
    required Color hairline,
    required SystemUiOverlayStyle overlay,
  }) {
    final textTheme = AppTypography.uiTextTheme(base.textTheme, text);
    final cupertino =
        base.platform == TargetPlatform.iOS ||
        base.platform == TargetPlatform.macOS;
    return base.copyWith(
      colorScheme: ColorScheme(
        brightness: base.brightness,
        primary: primary,
        onPrimary: onPrimary,
        secondary: primary,
        onSecondary: onPrimary,
        error: const Color(0xFF8C3A3A),
        onError: Colors.white,
        surface: surface,
        onSurface: text,
      ),
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      splashFactory: cupertino
          ? NoSplash.splashFactory
          : InkRipple.splashFactory,
      highlightColor: cupertino ? muted.withValues(alpha: 0.12) : null,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlay,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      dividerColor: hairline,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: hairline),
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

extension ThemeExtras on ThemeData {
  Color get mutedText =>
      brightness == Brightness.dark ? AppColors.darkMuted : AppColors.muted;

  Color get hairline => brightness == Brightness.dark
      ? AppColors.darkHairline
      : AppColors.hairline;

  Color statusWash(KanjiProgressStatus status) {
    final dark = brightness == Brightness.dark;
    return switch (status) {
      KanjiProgressStatus.notEncountered =>
        dark ? AppColors.darkSurface : Colors.white,
      KanjiProgressStatus.learning =>
        dark ? AppColors.darkLearningWash : AppColors.learningWash,
      KanjiProgressStatus.mastered =>
        dark ? AppColors.darkMasteredWash : AppColors.masteredWash,
    };
  }
}
