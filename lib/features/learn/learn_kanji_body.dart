import 'package:flutter/material.dart';

import '../../core/models/kanji_card.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common_words_section.dart';
import '../../widgets/mnemonic_text.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../stroke_order/kanji_stroke_animation.dart';

/// First meeting with a kanji: the character, what it means, and the story
/// that makes it stick.
///
/// Component characters are not listed here. The mnemonic already links each
/// building block, and a second list only repeated that.
class LearnKanjiBody extends StatelessWidget {
  const LearnKanjiBody({super.key, required this.card});

  final KanjiCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showMeaning =
        card.meaning.trim().isNotEmpty &&
        card.meaning.toLowerCase() != card.keyword.toLowerCase();

    return LayoutBuilder(
      builder: (context, constraints) {
        final body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: KanjiStrokeAnimation(
                character: card.character,
                size: _kanjiSide(constraints.maxHeight),
                showFrame: false,
                showStrokeNumbers: false,
                showFallbackCharacter: true,
              ),
            ),
            const SizedBox(height: 8),
            const SectionLabel('Meaning'),
            const SizedBox(height: 4),
            Text(
              card.keyword,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                height: 1.15,
              ),
            ),
            if (showMeaning) ...[
              const SizedBox(height: 2),
              Text(
                card.meaning,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.mutedText,
                  height: 1.25,
                ),
              ),
            ],
            if (card.hasReadings) ...[
              const SizedBox(height: 10),
              const SectionLabel('Readings'),
              const SizedBox(height: 4),
              _readings(theme),
            ],
            const SizedBox(height: 10),
            _mnemonic(theme),
            if (card.hasCommonWords) ...[
              const SizedBox(height: 10),
              CommonWordsSection(words: card.commonWords, compact: true),
            ],
          ],
        );

        if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
          return body;
        }

        // Scale the whole card down only when the phone is too short to show
        // it at full size. Nothing is tucked into a scroll view.
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(width: constraints.maxWidth, child: body),
        );
      },
    );
  }

  /// Glyph size, not including the stroke-order control under it.
  double _kanjiSide(double height) {
    const replay = 44.0;
    if (!height.isFinite || height <= 0) return 148;
    return (height * 0.28 - replay).clamp(72.0, 156.0);
  }

  /// On and kun on one line. A second row repeated the same two facts.
  Widget _readings(ThemeData theme) {
    final value = theme.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    final kind = value?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: theme.mutedText,
    );

    return Text.rich(
      TextSpan(
        children: [
          if (card.onyomi.isNotEmpty) ...[
            TextSpan(text: 'On ', style: kind),
            TextSpan(text: card.onyomiLabel, style: value),
          ],
          if (card.onyomi.isNotEmpty && card.kunyomi.isNotEmpty)
            TextSpan(text: '    ', style: kind),
          if (card.kunyomi.isNotEmpty) ...[
            TextSpan(text: 'Kun ', style: kind),
            TextSpan(text: card.kunyomiLabel, style: value),
          ],
        ],
      ),
    );
  }

  /// The mnemonic is the thing that makes the kanji stick, so it gets a
  /// surface of its own rather than trailing off as a footnote.
  Widget _mnemonic(ThemeData theme) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              components: card.componentModels,
              style: theme.textTheme.titleMedium!.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
