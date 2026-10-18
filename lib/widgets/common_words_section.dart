import 'package:flutter/material.dart';

import '../core/models/kanji_card.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import 'section_label.dart';

/// Compact list of everyday words for one kanji.
///
/// Renders nothing when [words] is empty or every entry is blank, so callers
/// can drop it in without an empty heading.
class CommonWordsSection extends StatelessWidget {
  const CommonWordsSection({
    super.key,
    required this.words,
    this.showHeading = true,
    this.compact = false,
  });

  final List<CommonWord> words;

  /// When false, only the entries are drawn. The kanji detail screen supplies
  /// its own section heading.
  final bool showHeading;

  /// Puts the word, reading, and meaning on one line when they fit. Used on
  /// the learn and answer screens, where the whole card has to stay in view.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final word in words)
        if (!word.isBlank) word,
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          const SectionLabel('Common Words'),
          SizedBox(height: compact ? 4 : 8),
        ],
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0)
            compact
                ? const SizedBox(height: 4)
                : Divider(height: 13, thickness: 1, color: theme.hairline),
          _CommonWordEntry(entry: entries[index], compact: compact),
        ],
      ],
    );
  }
}

class _CommonWordEntry extends StatelessWidget {
  const _CommonWordEntry({required this.entry, required this.compact});

  final CommonWord entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = entry.word.trim();
    final reading = entry.reading.trim();
    final meaning = entry.meaning.trim();
    final wordStyle = AppTypography.kanji(
      color: theme.colorScheme.onSurface,
      size: 20,
    ).copyWith(fontWeight: FontWeight.w600, height: 1.35);
    final readingStyle = AppTypography.kanji(
      color: theme.mutedText,
      size: 14,
    ).copyWith(fontWeight: FontWeight.w500, height: 1.35);
    final meaningStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 15,
      height: 1.35,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final wordAndReading = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            if (word.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Text(word, style: wordStyle),
              ),
            if (reading.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Text(reading, style: readingStyle),
              ),
            if (compact && meaning.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Text(meaning, style: meaningStyle),
              ),
          ],
        );

        if (compact || meaning.isEmpty) return wordAndReading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (word.isNotEmpty || reading.isNotEmpty) wordAndReading,
            if (meaning.isNotEmpty) ...[
              if (word.isNotEmpty || reading.isNotEmpty)
                const SizedBox(height: 2),
              Text(meaning, style: meaningStyle),
            ],
          ],
        );
      },
    );
  }
}
