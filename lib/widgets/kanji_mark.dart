import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';

/// A kanji presented as the focal point of a screen: large glyph, generous
/// space around it, and an optional halo that fades into the paper.
class KanjiMark extends StatelessWidget {
  const KanjiMark({
    super.key,
    required this.character,
    required this.size,
    this.halo = true,
    this.color,
    this.semanticsLabel,
  });

  final String character;
  final double size;
  final bool halo;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glyph = Text(
      character,
      textAlign: TextAlign.center,
      semanticsLabel: semanticsLabel,
      style: AppTypography.kanji(
        color: color ?? theme.colorScheme.onSurface,
        size: size,
      ),
    );

    if (!halo) return glyph;

    final diameter = size * 1.6;
    final wash = theme.accentWash.withValues(alpha: 0.6);

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [wash, wash.withValues(alpha: 0)],
                stops: const [0.42, 1],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          glyph,
        ],
      ),
    );
  }
}
