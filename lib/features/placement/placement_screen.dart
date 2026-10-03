import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/kanji_card.dart';
import '../../core/models/placement.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../services/placement_service.dart';
import '../../widgets/kanji_mark.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../onboarding/widgets/onboarding_scaffold.dart';
import 'placement_controller.dart';

/// Quick recognition pass that works out which kanji the user already knows.
///
/// Three states in one screen: the invitation, the kanji being asked about, and
/// the result. Nothing about an answer is ever shown back to the user — this is
/// calibration, not a quiz.
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
                  : "We'll show you some kanji to figure out\n"
                        'what you already know.',
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

  Future<void> _answer(BuildContext context, {required bool known}) async {
    HapticFeedback.lightImpact();
    await controller.answer(known: known);
  }

  @override
  Widget build(BuildContext context) {
    final card = controller.question;
    if (card == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return OnboardingScaffold(
      header: _PlacementProgress(controller: controller),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: 'I know it',
            onPressed: () => _answer(context, known: true),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: "I don't know it",
            onPressed: () => _answer(context, known: false),
          ),
        ],
      ),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SectionLabel(
              'Do you know this kanji?',
              align: TextAlign.center,
            ),
            SizedBox(height: height * 0.04),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _PlacementKanji(
                key: ValueKey(card.id),
                card: card,
                size: (height * 0.3).clamp(96.0, 164.0),
              ),
            ),
          ],
        );
      },
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
    final count = summary?.knownCount ?? 0;
    final level = summary?.startingLevel;

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
                  if (count > 0)
                    OnboardingStat(
                      value: '$count',
                      label: 'kanji already known',
                    )
                  else
                    Text(
                      _nothingFound(level),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  const SizedBox(height: 20),
                  const HairlineMark(width: 56),
                  const SizedBox(height: 20),
                  Text(
                    _startingPoint(level),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (count > 0) ...[
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
          ],
        );
      },
    );
  }

  /// A retake can find nothing left to place, which is not the same as a
  /// learner who is starting from scratch.
  String _nothingFound(JlptLevel? level) {
    return level == null
        ? 'Every kanji in the app is already in your reviews.'
        : "We'll start you from the beginning.";
  }

  /// One quiet line. No level is invented when the test cannot tell.
  String _startingPoint(JlptLevel? level) {
    if (level == null) return "That's every kanji in the app.";
    return switch (level) {
      JlptLevel.none => 'Your starting point is ready.',
      _ => 'Starting around ${level.sectionTitle}',
    };
  }
}
