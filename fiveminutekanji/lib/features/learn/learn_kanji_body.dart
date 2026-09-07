import 'package:flutter/material.dart';

import '../../core/models/kanji_card.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

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
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      card.character,
                      style: AppTypography.kanji(
                        color: theme.colorScheme.onSurface,
                        size: 112,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _sectionLabel(theme, 'Meaning'),
                const SizedBox(height: 8),
                Text(
                  card.keyword,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    height: 1.3,
                  ),
                ),
                if (showMeaning) ...[
                  const SizedBox(height: 6),
                  Text(
                    card.meaning,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.mutedText,
                      height: 1.45,
                    ),
                  ),
                ],
                if (card.hasReadings) ...[
                  const SizedBox(height: 24),
                  _sectionLabel(theme, 'Readings'),
                  const SizedBox(height: 8),
                  if (card.onyomi.isNotEmpty)
                    Text(
                      'On: ${card.onyomiLabel}',
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                  if (card.kunyomi.isNotEmpty)
                    Text(
                      'Kun: ${card.kunyomiLabel}',
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                ],
                if (showComponents) ...[
                  const SizedBox(height: 24),
                  _sectionLabel(theme, 'Components'),
                  const SizedBox(height: 8),
                  Text(
                    card.componentsLabel,
                    style: AppTypography.kanji(
                      color: theme.colorScheme.onSurface,
                      size: 22,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _sectionLabel(theme, 'Mnemonic'),
                const SizedBox(height: 8),
                Text(
                  card.mnemonic,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(ThemeData theme, String label) {
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.mutedText,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
