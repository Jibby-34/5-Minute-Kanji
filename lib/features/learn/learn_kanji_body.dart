import 'package:flutter/material.dart';

import '../../core/models/kanji_card.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/mnemonic_text.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../stroke_order/kanji_stroke_animation.dart';

/// First meeting with a kanji: the character, then what it means, then the
/// details that help it stick.
class LearnKanjiBody extends StatelessWidget {
  const LearnKanjiBody({super.key, required this.card});

  final KanjiCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showComponents = card.hasComponentBreakdown;
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
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Column(
                // Spare height is shared above and below rather than left as
                // a gap under the card.
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KanjiStrokeAnimation(
                    character: card.character,
                    size: kanjiSide,
                    showFrame: false,
                    showStrokeNumbers: false,
                    showFallbackCharacter: true,
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('Meaning'),
                  const SizedBox(height: 8),
                  Text(
                    card.keyword,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  if (showMeaning) ...[
                    const SizedBox(height: 6),
                    Text(
                      card.meaning,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.mutedText,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (card.hasReadings) ...[
                    const SizedBox(height: 22),
                    const SectionLabel('Readings'),
                    const SizedBox(height: 8),
                    if (card.onyomi.isNotEmpty)
                      _readingRow(theme, 'On', card.onyomiLabel),
                    if (card.kunyomi.isNotEmpty)
                      _readingRow(theme, 'Kun', card.kunyomiLabel),
                  ],
                  if (showComponents) ...[
                    const SizedBox(height: 20),
                    const SectionLabel('Components'),
                    const SizedBox(height: 6),
                    Text(
                      card.componentsLabel,
                      style: AppTypography.kanji(
                        color: theme.colorScheme.onSurface,
                        size: 24,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
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
    if (!height.isFinite || height <= 0) return 160;
    const replay = 44.0;
    return (height * 0.3 - replay).clamp(132.0, 176.0);
  }

  Widget _readingRow(ThemeData theme, String kind, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 44,
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
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The mnemonic is the thing that makes the kanji stick, so it gets a
  /// surface of its own rather than trailing off as a footnote.
  Widget _mnemonic(ThemeData theme) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.lightbulb_outline,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MnemonicText(
              mnemonic: card.mnemonic,
              components: card.components,
              style: theme.textTheme.titleMedium!.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
