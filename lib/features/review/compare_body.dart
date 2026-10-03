import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/onboarding.dart';
import '../../core/theme/app_theme.dart';
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

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Column(
                // Spare height is shared above and below rather than left as
                // a gap under the mnemonic.
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel(
                    'How did you do?',
                    align: TextAlign.center,
                  ),
                  const OnboardingHintText(
                    OnboardingHint.compareDrawing,
                    padding: EdgeInsets.only(top: 8),
                  ),
                  const SizedBox(height: 20),
                  _comparison(theme, side),
                  const SizedBox(height: 28),
                  Text(
                    card.keyword,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  if (showSecondaryMeaning) ...[
                    const SizedBox(height: 6),
                    Text(
                      card.meaning,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.mutedText,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (card.hasReadings) ...[
                    const SizedBox(height: 12),
                    _readings(theme),
                  ],
                  const SizedBox(height: 6),
                  Center(child: _strokeOrderButton(theme)),
                  const SizedBox(height: 10),
                  _mnemonic(theme),
                ],
              ),
            ),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

  double _compareSide(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth;
    final maxHeight = constraints.maxHeight;
    final widthBudget = ((maxWidth - 14) / 2).clamp(104.0, 162.0);
    if (!maxHeight.isFinite || maxHeight <= 0) return widthBudget;
    const headingAndLabels = 52.0;
    final heightBudget = (maxHeight * 0.34 - headingAndLabels).clamp(
      104.0,
      162.0,
    );
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
