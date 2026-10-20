import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/onboarding.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common_words_section.dart';
import '../../widgets/meaning_and_readings.dart';
import '../../widgets/mnemonic_card.dart';
import '../../widgets/section_label.dart';
import '../../widgets/study_content_scroll.dart';
import '../onboarding/widgets/onboarding_hint_text.dart';
import '../stroke_order/kanji_stroke_animation.dart';
import 'widgets/handwriting_pad.dart';

/// Post-submit self-evaluation: compare the frozen drawing to the correct
/// kanji.
///
/// The two sheets lead. Meaning, readings, and stroke order sit just
/// underneath, then the same mnemonic and vocabulary as the learn screen.
class CompareBody extends StatefulWidget {
  const CompareBody({super.key, required this.card, required this.drawing});

  final KanjiCard card;
  final HandwritingInput drawing;

  @override
  State<CompareBody> createState() => _CompareBodyState();
}

class _CompareBodyState extends State<CompareBody> {
  final _strokeOrder = GlobalKey<KanjiStrokeAnimationState>();

  KanjiCard get card => widget.card;

  static const _groupGap = 20.0;
  static const _panelGap = 12.0;
  static const _maxPanelSide = 196.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = _compareSide(constraints.maxWidth);
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('How did you do?', align: TextAlign.center),
            const OnboardingHintText(
              OnboardingHint.compareDrawing,
              padding: EdgeInsets.only(top: 8),
            ),
            const SizedBox(height: 8),
            _comparison(theme, side),
            const SizedBox(height: _groupGap),
            MeaningAndReadings(card: card, trailing: _strokeOrderButton(theme)),
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

  Widget _comparison(ThemeData theme, double side) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeledSquare(
          label: 'Your drawing',
          side: side,
          child: HandwritingPad(value: widget.drawing, readOnly: true),
        ),
        const SizedBox(width: _panelGap),
        _labeledSquare(
          label: 'Correct',
          side: side,
          child: _PaperFrame(
            child: KanjiStrokeAnimation(
              key: _strokeOrder,
              character: card.character,
              autoPlay: false,
              startCompleted: true,
              size: math.max(0.0, side - 16),
              showReplay: false,
              showFrame: false,
              showStrokeNumbers: false,
              showFallbackCharacter: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _labeledSquare({
    required String label,
    required double side,
    required Widget child,
  }) {
    return SizedBox(
      width: side,
      child: Column(
        children: [
          SectionLabel(label, align: TextAlign.center),
          const SizedBox(height: 8),
          SizedBox(width: side, height: side, child: child),
        ],
      ),
    );
  }

  Widget _strokeOrderButton(ThemeData theme) {
    return Tooltip(
      message: 'Replay stroke order',
      child: TextButton.icon(
        onPressed: () => _strokeOrder.currentState?.restart(),
        icon: const Icon(Icons.replay, size: 16),
        label: const Text('Stroke Order'),
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          padding: const EdgeInsets.fromLTRB(0, 4, 12, 4),
          minimumSize: const Size(48, 40),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.compact,
          textStyle: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Two equal sheets. Width sets the size; a cap keeps a tablet from
  /// turning the comparison into the whole page.
  double _compareSide(double maxWidth) {
    if (!maxWidth.isFinite || maxWidth <= _panelGap) return 48;
    final fitted = (maxWidth - _panelGap) / 2;
    // Floor so the pair cannot overflow the row by a fraction of a pixel.
    return math.min(fitted, _maxPanelSide).floorToDouble();
  }
}

/// Mirrors the handwriting pad so the correct kanji reads as the same sheet of
/// paper the user just drew on.
class _PaperFrame extends StatelessWidget {
  const _PaperFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardWash,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: theme.hairline),
      ),
      child: Center(child: child),
    );
  }
}
