import 'dart:async';

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
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/clock.dart';
import '../../repositories/kanji_repository.dart';
import '../../repositories/progress_repository.dart';
import '../../services/curriculum/curriculum_access.dart';
import '../../services/daily_workload.dart';
import '../../services/shake_detector.dart';
import '../../services/srs_scheduler.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/writing_sheet_layout.dart';
import '../learn/learn_kanji_body.dart';
import '../learn/practice_writing_body.dart';
import '../onboarding/widgets/onboarding_hint_text.dart';
import '../purchase/review_limit_prompt.dart';
import '../session_complete/session_complete_screen.dart';
import 'compare_body.dart';
import 'review_controller.dart';

/// Builds what replaces the session when it ends. See
/// [ReviewScreen.onSessionComplete].
typedef SessionCompleteBuilder =
    Widget Function(SessionSummary summary, StartOfDay startOfDay);

/// The deck is absent in a few widget tests that host a session directly.
DailyWorkloadService? _workloadService(
  BuildContext context,
  ProgressRepository progressRepository,
) {
  try {
    return DailyWorkloadService(
      kanjiRepository: context.read<KanjiRepository>(),
      progressRepository: progressRepository,
      curriculumAccess: _curriculumAccess(context),
    );
  } on ProviderNotFoundException {
    return null;
  }
}

CurriculumAccess? _curriculumAccess(BuildContext context) {
  try {
    return context.read<CurriculumAccess>();
  } on ProviderNotFoundException {
    return null;
  }
}

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({
    super.key,
    required this.cards,
    required this.config,
    this.isPractice = false,
    this.isStudyAnyway = false,
    this.clock,
    this.onSessionComplete,
    this.shakeEvents,
  });

  final List<KanjiCard> cards;
  final ReviewSessionConfig config;
  final bool isPractice;

  /// Optional overflow after the planned sitting. Still a real review.
  final bool isStudyAnyway;
  final Clock? clock;

  /// Replaces the usual summary screen. Used once, for the first session.
  final SessionCompleteBuilder? onSessionComplete;

  /// Shake source for undo. When null, phones listen to the accelerometer
  /// and every other platform stays quiet.
  final ShakeEvents? shakeEvents;

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
        final progressRepository = context.read<ProgressRepository>();
        final controller = ReviewController(
          progressRepository: progressRepository,
          srsEngine: context.read<SrsScheduler>(),
          cards: cards,
          config: config,
          isPractice: isPractice,
          isStudyAnyway: isStudyAnyway,
          clock: clock,
          workloadService: _workloadService(context, progressRepository),
          curriculumAccess: _curriculumAccess(context),
        );
        controller.hydrate();
        return controller;
      },
      child: _ReviewHost(
        isPractice: isPractice,
        onSessionComplete: onSessionComplete,
        shakeEvents: shakeEvents,
      ),
    );
  }
}

/// Keeps today's review clock in step with the app lifecycle. Background time
/// is paused and written out so a later sitting continues the same day.
class _ReviewHost extends StatefulWidget {
  const _ReviewHost({
    required this.isPractice,
    this.onSessionComplete,
    this.shakeEvents,
  });

  final bool isPractice;
  final SessionCompleteBuilder? onSessionComplete;
  final ShakeEvents? shakeEvents;

  @override
  State<_ReviewHost> createState() => _ReviewHostState();
}

class _ReviewHostState extends State<_ReviewHost> with WidgetsBindingObserver {
  ReviewController? _controller;
  bool _limitPromptRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.isPractice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeShowLimitPrompt());
      });
    }
  }

  Future<void> _maybeShowLimitPrompt() async {
    if (_limitPromptRequested || !mounted) return;
    final access = _curriculumAccess(context);
    if (access == null) return;
    _limitPromptRequested = true;
    await access.ensureLoaded();
    if (!mounted || !access.trialLimitReached) return;
    await showReviewLimitPrompt(context, access);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = context.read<ReviewController>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) {
      controller.pauseReviewTime();
      unawaited(controller.checkpointReviewTime());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        controller.pauseReviewTime();
        unawaited(controller.checkpointReviewTime());
      case AppLifecycleState.resumed:
        controller.resumeReviewTime();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ReviewView(
      onSessionComplete: widget.onSessionComplete,
      shakeEvents: widget.shakeEvents,
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({this.onSessionComplete, this.shakeEvents});

  final SessionCompleteBuilder? onSessionComplete;
  final ShakeEvents? shakeEvents;

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
    if (!context.mounted) return;
    if (controller.takeShakeUndoHint()) {
      _showReviewNotice(context, _shakeUndoDiscoveryMessage);
    }
    if (summary == null) return;
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

  Future<void> _showSummary(
    BuildContext context,
    SessionSummary summary,
  ) async {
    final startOfDay = context.read<ReviewController>().startOfDay;
    final replacement = onSessionComplete?.call(summary, startOfDay);
    if (summary.canContinue && replacement == null) {
      final keepGoing = await Navigator.of(context).push<bool>(
        AppRoutes.session(
          context,
          SessionCompleteScreen(summary: summary, startOfDay: startOfDay),
        ),
      );
      if (!context.mounted) return;
      if (keepGoing == true) {
        final next = await context
            .read<ReviewController>()
            .continuePastAllotment();
        if (!context.mounted || next == null) return;
        await _showSummary(context, next);
        return;
      }
      Navigator.of(context).pop();
      return;
    }

    await Navigator.of(context).pushReplacement(
      AppRoutes.session(
        context,
        replacement ??
            SessionCompleteScreen(summary: summary, startOfDay: startOfDay),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReviewController>();
    final card = controller.current;
    final theme = Theme.of(context);

    if (!controller.ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (card == null) {
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

    return Scaffold(
      body: _ShakeUndoRegion(
        shakeEvents: shakeEvents,
        child: SafeArea(
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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () async {
                        final controller = context.read<ReviewController>();
                        controller.pauseReviewTime();
                        await controller.checkpointReviewTime();
                        if (!context.mounted) return;
                        Navigator.of(context).maybePop();
                      },
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
                              isOnboarding: _isOnboardingRating(context),
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
        final again = controller.busy
            ? null
            : () => _rate(context, ReviewResult.again);
        final good = controller.busy
            ? null
            : () => _rate(context, ReviewResult.good);
        if (_isOnboardingRating(context)) {
          return Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _MissedItButton(onPressed: again),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: PrimaryButton(label: 'Got it', onPressed: good),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            RatingButton(label: 'Again', onPressed: again),
            RatingButton(label: 'Good', isPrimary: true, onPressed: good),
          ],
        );
    }
  }
}

/// True only while the first compare / first rating is still owed.
///
/// Both hints are cleared by the same tap, so later cards in the session and
/// every later session use the normal rating screen.
bool _isOnboardingRating(BuildContext context) {
  final hints = OnboardingHintScope.maybeOf(context);
  if (hints == null) return false;
  return hints.shouldShow(OnboardingHint.compareDrawing) ||
      hints.shouldShow(OnboardingHint.rateRecall);
}

const _shakeUndoDiscoveryMessage =
    'Made a mistake? Shake your phone to undo your last answer.';

const _shakeUndoConfirmationMessage = 'Last answer undone';

const _shakeUndoDiscoveryDuration = Duration(milliseconds: 4500);

const _shakeUndoConfirmationDuration = Duration(seconds: 2);

void _showReviewNotice(
  BuildContext context,
  String message, {
  Duration duration = _shakeUndoDiscoveryDuration,
}) {
  final theme = Theme.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final bottom = MediaQuery.viewPaddingOf(context).bottom;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.35,
        ),
      ),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: theme.brightness == Brightness.dark
          ? AppColors.darkSurface
          : AppColors.paperDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.hairline),
      ),
      // Sits above the action bar so Again / Good stay tappable.
      margin: EdgeInsets.fromLTRB(20, 0, 20, 128 + bottom),
    ),
  );
}

/// Listens for shakes while this review is on screen, and stops when it goes.
class _ShakeUndoRegion extends StatefulWidget {
  const _ShakeUndoRegion({required this.child, this.shakeEvents});

  final Widget child;
  final ShakeEvents? shakeEvents;

  @override
  State<_ShakeUndoRegion> createState() => _ShakeUndoRegionState();
}

class _ShakeUndoRegionState extends State<_ShakeUndoRegion> {
  StreamSubscription<void>? _shakes;

  @override
  void initState() {
    super.initState();
    final events = widget.shakeEvents ?? sensorShakeEventsForPlatform();
    if (events == null) return;
    try {
      _shakes = events.watch().listen(
        (_) => unawaited(_onShake()),
        onError: (Object _) {},
        cancelOnError: true,
      );
    } catch (_) {
      _shakes = null;
    }
  }

  @override
  void dispose() {
    final shakes = _shakes;
    _shakes = null;
    if (shakes != null) unawaited(shakes.cancel());
    super.dispose();
  }

  Future<void> _onShake() async {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final controller = context.read<ReviewController>();
    final undone = await controller.undoLastAnswer();
    if (!mounted || !undone) return;
    final routeAfter = ModalRoute.of(context);
    if (routeAfter != null && !routeAfter.isCurrent) return;
    HapticFeedback.lightImpact();
    _showReviewNotice(
      context,
      _shakeUndoConfirmationMessage,
      duration: _shakeUndoConfirmationDuration,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Outlined peer of the filled "Got it" button. Same height and type, with
/// the secondary ink for the stroke so it does not read as a warning.
class _MissedItButton extends StatelessWidget {
  const _MissedItButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      height: AppTheme.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          disabledForegroundColor: theme.mutedText,
          backgroundColor: theme.colorScheme.surface,
          side: BorderSide(color: theme.mutedText, width: 1.5),
          minimumSize: const Size.fromHeight(AppTheme.buttonHeight),
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          ),
        ),
        child: const Text('Missed it'),
      ),
    );
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

  /// Original keyword block: 34px line plus the gap before the square.
  static const _originalHeader = 57.0;

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
          const OnboardingHintText(
            OnboardingHint.drawFromMemory,
            padding: EdgeInsets.only(bottom: 10),
          ),
          Text(
            card.keyword,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 42,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
