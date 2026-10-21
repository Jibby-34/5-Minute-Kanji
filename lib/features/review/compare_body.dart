import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common_words_section.dart';
import '../../widgets/meaning_and_readings.dart';
import '../../widgets/mnemonic_card.dart';
import '../../widgets/section_label.dart';
import '../../widgets/study_content_scroll.dart';
import '../stroke_order/kanji_stroke_animation.dart';
import 'widgets/handwriting_pad.dart';

/// Post-submit self-evaluation: compare the frozen drawing to the correct
/// kanji.
///
/// The two sheets lead. Meaning, readings, and stroke order sit just
/// underneath, then the same mnemonic and vocabulary as the learn screen.
///
/// The first time through, readings, stroke order, and vocabulary fold into
/// More so the comparison and the mnemonic can lead. Pass [isOnboarding] for
/// that pass. Later reviews keep the shared layout.
class CompareBody extends StatefulWidget {
  const CompareBody({
    super.key,
    required this.card,
    required this.drawing,
    this.isOnboarding = false,
  });

  final KanjiCard card;
  final HandwritingInput drawing;

  /// First-time rating screen. Does not change the layout used afterwards.
  final bool isOnboarding;

  @override
  State<CompareBody> createState() => _CompareBodyState();
}

class _CompareBodyState extends State<CompareBody> {
  final _strokeOrder = GlobalKey<KanjiStrokeAnimationState>();
  bool _moreOpen = false;

  KanjiCard get card => widget.card;

  static const _groupGap = 20.0;
  static const _panelGap = 12.0;
  static const _maxPanelSide = 196.0;

  /// Room between the square sheets, the keyword, and the mnemonic on the
  /// first rating screen. Larger than the usual group gap so those three
  /// read as separate steps.
  static const _onboardingBlockGap = 32.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.isOnboarding) {
          return _onboardingBody(theme, constraints);
        }

        final side = _compareSide(constraints.maxWidth);
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('How did you do?', align: TextAlign.center),
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

  /// Square sheets, then the keyword and mnemonic with open space between
  /// them. Extra height stays below the block instead of stretching the sheets.
  Widget _onboardingBody(ThemeData theme, BoxConstraints constraints) {
    return StudyContentScroll(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _guidedHeading(theme),
          const SizedBox(height: 16),
          _onboardingCards(constraints.maxWidth),
          const SizedBox(height: _onboardingBlockGap),
          _meaning(theme),
          const SizedBox(height: _onboardingBlockGap),
          MnemonicCard(
            mnemonic: card.mnemonic,
            components: card.componentModels,
            prominentLinks: true,
          ),
          const SizedBox(height: 8),
          _MoreDisclosure(
            open: _moreOpen,
            onToggle: () => setState(() => _moreOpen = !_moreOpen),
            child: _moreBody(theme),
          ),
        ],
      ),
    );
  }

  /// Your drawing and the correct kanji, each a square about half the width.
  Widget _onboardingCards(double maxWidth) {
    final width = maxWidth.isFinite ? maxWidth : 320.0;
    final side = math.max(48.0, ((width - _panelGap) / 2).floorToDouble());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _onboardingPanel(
          label: 'Your drawing',
          side: side,
          child: HandwritingPad(value: widget.drawing, readOnly: true),
        ),
        const SizedBox(width: _panelGap),
        _onboardingPanel(label: 'Correct', side: side, child: _fittedGlyph()),
      ],
    );
  }

  Widget _onboardingPanel({
    required String label,
    required double side,
    required Widget child,
  }) {
    return SizedBox(
      width: side,
      child: Column(
        children: [
          SectionLabel(label, align: TextAlign.center, fontSize: 13),
          const SizedBox(height: 8),
          SizedBox(width: side, height: side, child: child),
        ],
      ),
    );
  }

  Widget _fittedGlyph() {
    return _PaperFrame(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(
            0.0,
            math.min(constraints.maxWidth, constraints.maxHeight) - 16,
          );
          return KanjiStrokeAnimation(
            key: _strokeOrder,
            character: card.character,
            autoPlay: false,
            startCompleted: true,
            size: side,
            showReplay: false,
            showFrame: false,
            showStrokeNumbers: false,
            showFallbackCharacter: true,
          );
        },
      ),
    );
  }

  Widget _guidedHeading(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How did you do?',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Compare, then rate honestly.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.mutedText,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _meaning(ThemeData theme) {
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
              fontSize: 16,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }

  Widget _moreBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (card.hasReadings) ...[
          const SectionLabel('Readings'),
          const SizedBox(height: 8),
          _CompareReadings(
            onyomi: card.onyomiLabel,
            kunyomi: card.kunyomiLabel,
          ),
          const SizedBox(height: 4),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: _strokeOrderButton(theme),
        ),
        if (card.hasCommonWords) ...[
          const SizedBox(height: _groupGap),
          CommonWordsSection(words: card.commonWords, compact: true),
        ],
      ],
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
          SectionLabel(label, align: TextAlign.center, fontSize: 13),
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

/// Closed by default. Readings, stroke order, and vocabulary stay one tap away.
class _MoreDisclosure extends StatelessWidget {
  const _MoreDisclosure({
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Text(
                      'More',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.onSurface,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open) child,
      ],
    );
  }
}

class _CompareReadings extends StatelessWidget {
  const _CompareReadings({required this.onyomi, required this.kunyomi});

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
