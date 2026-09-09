import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/theme/app_theme.dart';
import '../stroke_order/kanji_stroke_animation.dart';
import 'widgets/handwriting_pad.dart';

/// Post-submit self-evaluation: compare the frozen drawing to the correct kanji.
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'How did you do?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _comparison(theme, side),
                  const SizedBox(height: 20),
                  Text(
                    card.keyword,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      height: 1.25,
                    ),
                  ),
                  if (showSecondaryMeaning) ...[
                    const SizedBox(height: 4),
                    Text(
                      card.meaning,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.mutedText,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (card.hasReadings) ...[
                    const SizedBox(height: 10),
                    if (card.onyomi.isNotEmpty)
                      _readingLine(theme, 'On', card.onyomiLabel),
                    if (card.kunyomi.isNotEmpty)
                      _readingLine(theme, 'Kun', card.kunyomiLabel),
                  ],
                  const SizedBox(height: 8),
                  Center(child: _strokeOrderButton(theme)),
                  const SizedBox(height: 8),
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
            theme: theme,
            label: 'Your drawing',
            side: side,
            child: HandwritingPad(value: widget.drawing, readOnly: true),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _labeledSquare(
            theme: theme,
            label: 'Correct',
            side: side,
            child: KanjiStrokeAnimation(
              key: _strokeOrder,
              character: card.character,
              autoPlay: false,
              startCompleted: true,
              size: side,
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
    required ThemeData theme,
    required String label,
    required double side,
    required Widget child,
  }) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.mutedText,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: SizedBox(width: side, height: side, child: child),
        ),
      ],
    );
  }

  Widget _readingLine(ThemeData theme, String kind, String value) {
    return Text(
      '$kind: $value',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.mutedText,
        height: 1.35,
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
          foregroundColor: theme.mutedText,
          minimumSize: const Size(48, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _mnemonic(ThemeData theme) {
    return Semantics(
      label: 'Memory aid: ${card.mnemonic}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, size: 18, color: theme.mutedText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                card.mnemonic,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.mutedText,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _compareSide(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth;
    final maxHeight = constraints.maxHeight;
    final widthBudget = ((maxWidth - 16) / 2).clamp(100.0, 130.0);
    if (!maxHeight.isFinite || maxHeight <= 0) return widthBudget;
    const headingAndLabels = 44.0;
    final heightBudget = (maxHeight * 0.28 - headingAndLabels).clamp(
      100.0,
      130.0,
    );
    return math.min(widthBudget, heightBudget);
  }
}
