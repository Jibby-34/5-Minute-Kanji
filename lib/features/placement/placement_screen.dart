import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/kanji_card.dart';
import '../../core/models/placement.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../services/placement_service.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';
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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (controller.phase) {
          PlacementPhase.loading ||
          PlacementPhase.saving => const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          PlacementPhase.intro => _PlacementIntro(controller: controller),
          PlacementPhase.asking => _PlacementQuestion(controller: controller),
          PlacementPhase.results => _PlacementResults(
            summary: controller.summary,
            onFinished: onFinished,
          ),
        },
      ),
    );
  }
}

class _PlacementIntro extends StatelessWidget {
  const _PlacementIntro({required this.controller});

  final PlacementController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resuming = controller.isResuming;

    return Column(
      children: [
        Expanded(
          child: _CenteredCopy(
            children: [
              Text(
                "Let's find your starting point",
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                resuming
                    ? 'Pick up where you left off.'
                    : "We'll show you some kanji to figure out what you "
                          'already know.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.mutedText,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'It only takes a couple minutes.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        BottomActionInset(
          child: PrimaryButton(
            label: resuming ? 'Continue' : 'Start Placement Test',
            onPressed: controller.start,
          ),
        ),
      ],
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
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return Column(
      children: [
        _PlacementProgress(controller: controller),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _PlacementKanji(key: ValueKey(card.id), card: card),
          ),
        ),
        BottomActionInset(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryButton(
                label: 'I know it',
                onPressed: () => _answer(context, known: true),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _answer(context, known: false),
                  child: const Text("I don't know it"),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlacementKanji extends StatelessWidget {
  const _PlacementKanji({super.key, required this.card});

  final KanjiCard card;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            card.character,
            style: AppTypography.kanji(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
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
          padding: EdgeInsets.fromLTRB(20, canClose ? 4 : 16, 4, 12),
          child: Row(
            children: [
              Text(
                '${controller.answeredCount + 1} / ~${controller.estimatedTotal}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.mutedText,
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: controller.progress),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 2,
              backgroundColor: theme.hairline,
              color: theme.colorScheme.primary,
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

    return Column(
      children: [
        Expanded(
          child: _CenteredCopy(
            children: [
              Text(
                "You're all set!",
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _found(count, level),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              if (_startingPoint(count, level) case final startingPoint?) ...[
                const SizedBox(height: 16),
                Text(
                  startingPoint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.mutedText,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        BottomActionInset(
          child: PrimaryButton(label: 'Start Learning', onPressed: onFinished),
        ),
      ],
    );
  }

  String _found(int count, JlptLevel? level) {
    if (count > 0) {
      return 'We found ${count == 1 ? '1 kanji' : '$count kanji'} '
          'you already know.';
    }
    // A retake can find nothing left to place, which is not the same as a
    // learner who is starting from scratch.
    return level == null
        ? 'Every kanji in the app is already in your reviews.'
        : "We'll start you from the beginning.";
  }

  /// Kept to one quiet line. The useful outcome is the known kanji, not a
  /// proficiency score.
  String? _startingPoint(int count, JlptLevel? level) {
    if (level == null) {
      return count > 0 ? "That's every kanji in the app." : null;
    }
    return switch (level) {
      JlptLevel.none => null,
      _ => 'Your starting point: around ${level.sectionTitle}',
    };
  }
}

/// Centred copy that scrolls instead of overflowing when type is scaled up.
class _CenteredCopy extends StatelessWidget {
  const _CenteredCopy({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        );
      },
    );
  }
}
