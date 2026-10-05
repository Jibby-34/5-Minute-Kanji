import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/onboarding.dart';
import '../../core/models/review.dart';
import '../../core/models/start_of_day.dart';
import '../../core/models/study_phase.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/clock.dart';
import '../../repositories/progress_repository.dart';
import '../../services/srs_scheduler.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';
import '../learn/learn_kanji_body.dart';
import '../learn/practice_writing_body.dart';
import '../onboarding/widgets/onboarding_hint_text.dart';
import '../session_complete/session_complete_screen.dart';
import 'compare_body.dart';
import 'review_controller.dart';
import 'widgets/handwriting_pad.dart';

/// Builds what replaces the session when it ends. See
/// [ReviewScreen.onSessionComplete].
typedef SessionCompleteBuilder =
    Widget Function(SessionSummary summary, StartOfDay startOfDay);

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({
    super.key,
    required this.cards,
    required this.config,
    this.isPractice = false,
    this.isStudyAnyway = false,
    this.clock,
    this.onSessionComplete,
  });

  final List<KanjiCard> cards;
  final ReviewSessionConfig config;
  final bool isPractice;

  /// Optional overflow after the planned sitting. Still a real review.
  final bool isStudyAnyway;
  final Clock? clock;

  /// Replaces the usual summary screen. Used once, for the first session.
  final SessionCompleteBuilder? onSessionComplete;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Expanded(
                child: Center(child: Text('Nothing to review right now.')),
              ),
            ],
          ),
        ),
      );
    }

    return ChangeNotifierProvider(
      create: (context) {
        final controller = ReviewController(
          progressRepository: context.read<ProgressRepository>(),
          srsEngine: context.read<SrsScheduler>(),
          cards: cards,
          config: config,
          isPractice: isPractice,
          isStudyAnyway: isStudyAnyway,
          clock: clock,
        );
        controller.hydrate();
        return controller;
      },
      child: _ReviewView(onSessionComplete: onSessionComplete),
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({this.onSessionComplete});

  final SessionCompleteBuilder? onSessionComplete;

  Future<void> _submit(BuildContext context) async {
    HapticFeedback.lightImpact();
    OnboardingHintScope.maybeOf(
      context,
    )?.dismiss(OnboardingHint.drawFromMemory);
    context.read<ReviewController>().submit();
  }

  Future<void> _rate(BuildContext context, ReviewResult result) async {
    if (result == ReviewResult.again) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    OnboardingHintScope.maybeOf(context)?.dismissAll(const [
      OnboardingHint.compareDrawing,
      OnboardingHint.rateRecall,
    ]);
    final controller = context.read<ReviewController>();
    final summary = await controller.rate(result);
    if (!context.mounted || summary == null) return;
    await _showSummary(context, summary);
  }

  Future<void> _finishLearning(BuildContext context) async {
    final controller = context.read<ReviewController>();
    final summary = await controller.completePractice();
    if (!context.mounted || summary == null) return;
    await _showSummary(context, summary);
  }

  Future<void> _markAsKnown(BuildContext context) async {
    final controller = context.read<ReviewController>();
    final summary = await controller.markCurrentAsKnown();
    if (!context.mounted || summary == null) return;
    await _showSummary(context, summary);
  }

  Future<void> _showSummary(BuildContext context, SessionSummary summary) {
    final startOfDay = context.read<ReviewController>().startOfDay;
    return Navigator.of(context).pushReplacement(
      AppRoutes.session(
        context,
        onSessionComplete?.call(summary, startOfDay) ??
            SessionCompleteScreen(summary: summary, startOfDay: startOfDay),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReviewController>();
    final card = controller.current;
    final theme = Theme.of(context);

    if (!controller.ready || card == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Text(
                    '${controller.remainingToDraw} remaining',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.mutedText,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: SizedBox(
                        key: ValueKey(
                          '${controller.phase}-${card.id}-${controller.padGeneration}',
                        ),
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: switch (controller.phase) {
                          StudyPhase.learn => LearnKanjiBody(
                            key: ValueKey('learn-${card.id}'),
                            card: card,
                          ),
                          StudyPhase.practice => PracticeWritingBody(
                            key: ValueKey(
                              'practice-${card.id}-${controller.padGeneration}',
                            ),
                            card: card,
                            drawing: controller.drawing,
                            onDrawingChanged: controller.updateDrawing,
                          ),
                          StudyPhase.compare => CompareBody(
                            key: ValueKey('compare-${card.id}'),
                            card: card,
                            drawing:
                                controller.answer?.drawing ??
                                controller.drawing,
                          ),
                          StudyPhase.recall => _PromptBody(
                            key: ValueKey(
                              'prompt-${card.id}-${controller.padGeneration}',
                            ),
                            card: card,
                            drawing: controller.drawing,
                            onDrawingChanged: controller.updateDrawing,
                          ),
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            BottomActionInset(child: _actions(context, controller)),
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, ReviewController controller) {
    switch (controller.phase) {
      case StudyPhase.learn:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              label: 'Practice Writing',
              onPressed: controller.busy ? null : controller.beginPractice,
            ),
            if (!controller.isPractice) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: controller.busy ? null : () => _markAsKnown(context),
                child: Text(
                  'Already know this? Mark as known',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).mutedText,
                  ),
                ),
              ),
            ],
          ],
        );
      case StudyPhase.practice:
        return PrimaryButton(
          label: 'Done',
          onPressed: controller.busy ? null : () => _finishLearning(context),
        );
      case StudyPhase.recall:
        return PrimaryButton(
          label: 'Submit',
          onPressed: controller.busy ? null : () => _submit(context),
        );
      case StudyPhase.compare:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OnboardingHintText(
              OnboardingHint.rateRecall,
              padding: EdgeInsets.only(left: 8, right: 8, bottom: 12),
            ),
            Row(
              children: [
                RatingButton(
                  label: 'Again',
                  onPressed: controller.busy
                      ? null
                      : () => _rate(context, ReviewResult.again),
                ),
                RatingButton(
                  label: 'Good',
                  isPrimary: true,
                  onPressed: controller.busy
                      ? null
                      : () => _rate(context, ReviewResult.good),
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _PromptBody extends StatelessWidget {
  const _PromptBody({
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
        const OnboardingHintText(
          OnboardingHint.drawFromMemory,
          padding: EdgeInsets.only(top: 8),
        ),
        const SizedBox(height: 18),
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
