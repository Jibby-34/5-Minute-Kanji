import 'package:flutter/material.dart';

import '../core/models/kanji_card.dart';
import '../core/theme/app_theme.dart';
import 'section_label.dart';

/// Meaning and readings, packed as one block on the learn and answer screens.
///
/// [trailing] sits with the readings. The answer screen uses it for stroke
/// order; the learn screen puts that control under the kanji instead.
class MeaningAndReadings extends StatelessWidget {
  const MeaningAndReadings({super.key, required this.card, this.trailing});

  final KanjiCard card;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showMeaning =
        card.meaning.trim().isNotEmpty &&
        card.meaning.toLowerCase() != card.keyword.toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Meaning'),
        const SizedBox(height: 8),
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
          const SizedBox(height: 4),
          Text(
            card.meaning,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.mutedText,
              height: 1.25,
            ),
          ),
        ],
        if (card.hasReadings) ...[
          const SizedBox(height: 12),
          const SectionLabel('Readings'),
          const SizedBox(height: 8),
          _Readings(onyomi: card.onyomiLabel, kunyomi: card.kunyomiLabel),
        ],
        if (trailing != null) ...[
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: trailing!),
        ],
      ],
    );
  }
}

class _Readings extends StatelessWidget {
  const _Readings({required this.onyomi, required this.kunyomi});

  final String onyomi;
  final String kunyomi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = theme.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );
    final kind = value?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: theme.mutedText,
    );

    return Text.rich(
      TextSpan(
        children: [
          if (onyomi.isNotEmpty) ...[
            TextSpan(text: 'On ', style: kind),
            TextSpan(text: onyomi, style: value),
          ],
          if (onyomi.isNotEmpty && kunyomi.isNotEmpty)
            TextSpan(text: '    ', style: kind),
          if (kunyomi.isNotEmpty) ...[
            TextSpan(text: 'Kun ', style: kind),
            TextSpan(text: kunyomi, style: value),
          ],
        ],
      ),
    );
  }
}
