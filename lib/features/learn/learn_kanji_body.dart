import 'package:flutter/material.dart';

import '../../core/models/kanji_card.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../stroke_order/kanji_stroke_animation.dart';

class LearnKanjiBody extends StatelessWidget {
  const LearnKanjiBody({super.key, required this.card});

  final KanjiCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showComponents =
        card.components.length > 1 ||
        (card.components.length == 1 &&
            card.components.first != card.character);
    final showMeaning =
        card.meaning.trim().isNotEmpty &&
        card.meaning.toLowerCase() != card.keyword.toLowerCase();

    return LayoutBuilder(
      builder: (context, constraints) {
        final kanjiSide = _kanjiSide(constraints);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KanjiStrokeAnimation(
                    character: card.character,
                    size: kanjiSide,
                    showFrame: false,
                    showStrokeNumbers: false,
                    showFallbackCharacter: true,
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(theme, 'Meaning'),
                  const SizedBox(height: 6),
                  Text(
                    card.keyword,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      height: 1.25,
                    ),
                  ),
                  if (showMeaning) ...[
                    const SizedBox(height: 4),
                    Text(
                      card.meaning,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.mutedText,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (card.hasReadings) ...[
                    const SizedBox(height: 20),
                    _sectionLabel(theme, 'Readings'),
                    const SizedBox(height: 6),
                    if (card.onyomi.isNotEmpty)
                      _readingRow(theme, 'On', card.onyomiLabel),
                    if (card.kunyomi.isNotEmpty)
                      _readingRow(theme, 'Kun', card.kunyomiLabel),
                  ],
                  if (showComponents) ...[
                    const SizedBox(height: 16),
                    _sectionLabel(theme, 'Components'),
                    const SizedBox(height: 4),
                    Text(
                      card.componentsLabel,
                      style: AppTypography.kanji(
                        color: theme.colorScheme.onSurface,
                        size: 20,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _mnemonic(theme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  double _kanjiSide(BoxConstraints constraints) {
    final height = constraints.maxHeight;
    if (!height.isFinite || height <= 0) return 156;
    const replay = 44.0;
    return (height * 0.29 - replay).clamp(128.0, 168.0);
  }

  Widget _sectionLabel(ThemeData theme, String label) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.mutedText,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        height: 1.2,
      ),
    );
  }

  Widget _readingRow(ThemeData theme, String kind, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              kind,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.mutedText,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mnemonic(ThemeData theme) {
    return Semantics(
      label: 'Memory aid: ${card.mnemonic}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, size: 18, color: theme.mutedText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                card.mnemonic,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.mutedText,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
