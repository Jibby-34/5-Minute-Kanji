import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/onboarding.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common_words_section.dart';
import '../../widgets/mnemonic_text.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../onboarding/widgets/onboarding_hint_text.dart';
import '../stroke_order/kanji_stroke_animation.dart';
import 'widgets/handwriting_pad.dart';

/// Post-submit self-evaluation: compare the frozen drawing to the correct
/// kanji.
///
/// The answer is the point of this screen, so the two squares, the meaning and
/// the mnemonic carry the weight; the question above them is just a label.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSecondaryMeaning =
        card.meaning.trim().isNotEmpty &&
        card.meaning.toLowerCase() != card.keyword.toLowerCase();

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = _compareSide(constraints);
        final body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('How did you do?', align: TextAlign.center),
            const OnboardingHintText(
              OnboardingHint.compareDrawing,
              padding: EdgeInsets.only(top: 6),
            ),
            const SizedBox(height: 8),
            _comparison(theme, side),
            const SizedBox(height: 12),
            Text(
              card.keyword,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            if (showSecondaryMeaning) ...[
              const SizedBox(height: 2),
              Text(
                card.meaning,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.mutedText,
                  height: 1.25,
                ),
              ),
            ],
            if (card.hasReadings) ...[
              const SizedBox(height: 6),
              _readings(theme),
            ],
            Center(child: _strokeOrderButton(theme)),
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

        // The drawing, the answer, and the vocabulary stay on one screen.
        // Short phones scale the card down instead of scrolling it.
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(width: constraints.maxWidth, child: body),
        );
      },
    );
  }

  Widget _comparison(ThemeData theme, double side) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _labeledSquare(
            label: 'Your drawing',
            side: side,
            child: HandwritingPad(value: widget.drawing, readOnly: true),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _labeledSquare(
            label: 'Correct',
            side: side,
            child: _PaperFrame(
              child: KanjiStrokeAnimation(
                key: _strokeOrder,
                character: card.character,
                autoPlay: false,
                startCompleted: true,
                size: side - 20,
                showReplay: false,
                showFrame: false,
                showStrokeNumbers: false,
                showFallbackCharacter: true,
              ),
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
    return Column(
      children: [
        SectionLabel(label, align: TextAlign.center),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(width: side, height: side, child: child),
        ),
      ],
    );
  }

  /// On and kun readings on one line, big enough to actually read.
  Widget _readings(ThemeData theme) {
    final value = theme.textTheme.titleLarge?.copyWith(
      fontSize: 19,
      fontWeight: FontWeight.w500,
      height: 1.35,
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
            TextSpan(text: '  ·  ', style: kind),
          if (card.kunyomi.isNotEmpty) ...[
            TextSpan(text: 'Kun ', style: kind),
            TextSpan(text: card.kunyomiLabel, style: value),
          ],
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _strokeOrderButton(ThemeData theme) {
    return Tooltip(
      message: 'Replay stroke order',
      child: TextButton.icon(
        onPressed: () => _strokeOrder.currentState?.restart(),
        icon: const Icon(Icons.replay, size: 17),
        label: const Text('Stroke Order'),
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          textStyle: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          minimumSize: const Size(48, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  /// The mnemonic is learning content, so it gets a surface of its own rather
  /// than trailing off as a footnote.
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

  double _compareSide(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth;
    final maxHeight = constraints.maxHeight;
    final widthBudget = maxWidth.isFinite
        ? ((maxWidth - 14) / 2).clamp(72.0, 136.0)
        : 120.0;
    if (!maxHeight.isFinite || maxHeight <= 0) return widthBudget;
    final heightBudget = (maxHeight * 0.24).clamp(72.0, 136.0);
    return math.min(widthBudget, heightBudget);
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
