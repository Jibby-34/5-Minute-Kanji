import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/kanji_card.dart';
import '../../core/models/placement.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../services/placement_choices.dart';
import '../../services/placement_service.dart';
import '../../widgets/kanji_mark.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../onboarding/widgets/onboarding_scaffold.dart';
import 'placement_controller.dart';

/// Quick meaning quiz that works out which kanji the user already knows.
///
/// Three states in one screen: the invitation, a kanji with four meanings, and
/// the result. A tap moves straight to the next kanji. Nothing marks the
/// choice right or wrong.
class PlacementScreen extends StatelessWidget {
  const PlacementScreen({super.key, required this.onFinished});

  /// Called when the user leaves the results screen.
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          PlacementController(service: context.read<PlacementService>())
            ..load(),
      child: _PlacementView(onFinished: onFinished),
    );
  }
}

class _PlacementView extends StatelessWidget {
  const _PlacementView({required this.onFinished});

  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlacementController>();

    return switch (controller.phase) {
      PlacementPhase.loading || PlacementPhase.saving => const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      PlacementPhase.intro => _PlacementIntro(controller: controller),
      PlacementPhase.asking => _PlacementQuestion(controller: controller),
      PlacementPhase.results => _PlacementResults(
        summary: controller.summary,
        onFinished: onFinished,
      ),
    };
  }
}

class _PlacementIntro extends StatelessWidget {
  const _PlacementIntro({required this.controller});

  final PlacementController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resuming = controller.isResuming;

    return OnboardingScaffold(
      step: 2,
      action: PrimaryButton(
        label: resuming ? 'Continue' : 'Start Placement Test',
        onPressed: controller.start,
      ),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LevelRamp(size: (height * 0.15).clamp(48.0, 88.0)),
            SizedBox(height: height * 0.08),
            OnboardingHeadline(
              label: 'Placement',
              title: "Let's find your starting point",
              subtitle: resuming
                  ? 'Pick up where you left off.'
                  : "We'll show you a kanji and ask\n"
                        'what it means.',
            ),
            const SizedBox(height: 14),
            Text(
              'It only takes a couple minutes.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.mutedText,
                height: 1.4,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Three kanji fading out: easy to hard, which is what the test is looking for.
class _LevelRamp extends StatelessWidget {
  const _LevelRamp({required this.size});

  final double size;

  static const _characters = ['日', '校', '議'];
  static const _alphas = [1.0, 0.45, 0.18];

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;

    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < _characters.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Text(
                _characters[index],
                style: AppTypography.kanji(
                  color: ink.withValues(alpha: _alphas[index]),
                  size: size,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlacementQuestion extends StatelessWidget {
  const _PlacementQuestion({required this.controller});

  final PlacementController controller;

  Future<void> _choose(BuildContext context, PlacementChoice choice) async {
    HapticFeedback.lightImpact();
    await controller.answer(known: choice.correct);
  }

  @override
  Widget build(BuildContext context) {
    final card = controller.question;
    final choices = controller.choices;
    if (card == null || choices.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return OnboardingScaffold(
      header: _PlacementProgress(controller: controller),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < choices.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _MeaningChoice(
              label: choices[index].label,
              onPressed: () => _choose(context, choices[index]),
            ),
          ],
        ],
      ),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SectionLabel('What does this mean?', align: TextAlign.center),
            SizedBox(height: height * 0.04),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _PlacementKanji(
                key: ValueKey(card.id),
                card: card,
                size: (height * 0.34).clamp(88.0, 148.0),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One of the four meanings. Every choice looks the same, so the styling
/// does not hint at the right one.
class _MeaningChoice extends StatelessWidget {
  const _MeaningChoice({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _PlacementKanji extends StatelessWidget {
  const _PlacementKanji({super.key, required this.card, required this.size});

  final KanjiCard card;
  final double size;

  @override
  Widget build(BuildContext context) {
    return KanjiMark(character: card.character, size: size);
  }
}

/// Deliberately quiet: a count and a hairline bar, no question numbers shouted
/// at the user.
class _PlacementProgress extends StatelessWidget {
  const _PlacementProgress({required this.controller});

  final PlacementController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canClose = Navigator.of(context).canPop();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            28,
            canClose ? 2 : 14,
            canClose ? 8 : 28,
            10,
          ),
          child: Row(
            children: [
              Text(
                '${controller.answeredCount + 1} / ~${controller.estimatedTotal}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.mutedText,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              if (canClose)
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: controller.progress),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: theme.hairline,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlacementResults extends StatelessWidget {
  const _PlacementResults({required this.summary, required this.onFinished});

  final PlacementSummary? summary;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final known = summary?.knownCount ?? 0;
    final confirming = summary?.confirmCount ?? 0;
    final nothing = summary?.nothingToPlace ?? false;
    final headline = summary?.headline ?? '';
    final detail = summary?.detail;

    return OnboardingScaffold(
      step: 2,
      action: PrimaryButton(label: 'Start Learning', onPressed: onFinished),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const OnboardingHeadline(
              label: 'Placement complete',
              title: "You're all set!",
            ),
            SizedBox(height: height * 0.06),
            SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
              child: Column(
                children: [
                  Text(
                    nothing
                        ? 'Every kanji in the app is already in your reviews.'
                        : headline.isEmpty
                        ? 'Your starting point is ready.'
                        : headline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  if (!nothing && detail != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (known > 0) ...[
              SizedBox(height: height * 0.04),
              Text(
                "We've added the kanji you already know to your library.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.mutedText,
                  height: 1.4,
                ),
              ),
            ],
            if (confirming > 0) ...[
              SizedBox(height: height * 0.02),
              Text(
                'Some others will come up in review so we can confirm them.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.mutedText,
                  height: 1.4,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
