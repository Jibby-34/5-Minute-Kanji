import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/kanji_card.dart';
import '../../widgets/common_words_section.dart';
import '../../widgets/meaning_and_readings.dart';
import '../../widgets/mnemonic_card.dart';
import '../../widgets/study_content_scroll.dart';
import '../stroke_order/kanji_stroke_animation.dart';

/// First meeting with a kanji: the character, what it means, and the story
/// that makes it stick.
///
/// Component characters are not listed here. The mnemonic already links each
/// building block, and a second list only repeated that.
class LearnKanjiBody extends StatelessWidget {
  const LearnKanjiBody({super.key, required this.card});

  final KanjiCard card;

  /// Large enough to lead the screen, small enough that the meaning stays
  /// close underneath on a phone.
  static const _kanjiSize = 156.0;

  static const _groupGap = 20.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: KanjiStrokeAnimation(
                character: card.character,
                size: _kanjiSide(constraints.maxWidth),
                showFrame: false,
                showStrokeNumbers: false,
                showFallbackCharacter: true,
                replayColor: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: _groupGap),
            MeaningAndReadings(card: card),
            const SizedBox(height: _groupGap),
            MnemonicCard(
              mnemonic: card.mnemonic,
              components: card.componentModels,
            ),
            if (card.hasCommonWords) ...[
              const SizedBox(height: _groupGap),
              CommonWordsSection(words: card.commonWords, compact: true),
            ],
          ],
        );

        return StudyContentScroll(child: content);
      },
    );
  }

  double _kanjiSide(double width) {
    if (!width.isFinite || width <= 0) return _kanjiSize;
    return math.min(_kanjiSize, width);
  }
}
