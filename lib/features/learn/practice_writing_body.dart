import 'package:flutter/material.dart';

import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../widgets/section_label.dart';
import '../../widgets/writing_sheet_layout.dart';
import '../stroke_order/kanji_stroke_animation.dart';

/// Copy the kanji once, with the handwritten form as the model.
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

  /// Original "Copy it below" block: label, gap, 72px glyph, gap.
  static const _originalHeader = 116.0;
  static const _kanjiSize = 96.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return WritingSheetLayout(
      drawing: drawing,
      onDrawingChanged: onDrawingChanged,
      headerHeight: _originalHeader,
      prompt: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SectionLabel(
            'Copy it below',
            align: TextAlign.center,
            fontSize: 14,
          ),
          const SizedBox(height: 8),
          KanjiStrokeAnimation(
            character: card.character,
            size: _kanjiSize,
            autoPlay: false,
            startCompleted: true,
            showFrame: false,
            showStrokeNumbers: false,
            showFallbackCharacter: true,
            replayColor: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
