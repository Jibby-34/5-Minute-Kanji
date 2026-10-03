import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/section_label.dart';
import '../review/widgets/handwriting_pad.dart';

class PracticeWritingBody extends StatelessWidget {
  const PracticeWritingBody({
    super.key,
    required this.card,
    required this.drawing,
    required this.onDrawingChanged,
  });

  final KanjiCard card;
  final HandwritingInput drawing;
  final ValueChanged<HandwritingInput> onDrawingChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        const SectionLabel('Copy it below'),
        const SizedBox(height: 10),
        Text(
          card.character,
          style: AppTypography.kanji(
            color: theme.colorScheme.onSurface,
            size: 72,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = math.min(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: HandwritingPad(
                    value: drawing,
                    onChanged: onDrawingChanged,
                    showClear: true,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
