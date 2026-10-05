import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/daily_goal.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/onboarding.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/notification_gateway.dart';
import '../../services/onboarding_service.dart';
import '../../services/placement_service.dart';
import '../../services/reminder_scheduler.dart';
import '../home/home_controller.dart';
import '../home/home_screen.dart';
import '../placement/placement_screen.dart';
import '../review/review_screen.dart';
import 'daily_goal_screen.dart';
import 'first_session_complete_screen.dart';
import 'reminder_prompt_screen.dart';
import 'welcome_screen.dart';

/// App root. Resumes the first-launch flow at whatever step it reached, and
/// renders Home for everyone who is past it.
///
/// The steps up to the daily goal replace Home; the first session and the
/// reminder question are routes pushed over it, so closing them leaves the
/// user in the app rather than stuck in onboarding.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  OnboardingStage? _stage;

  /// Guards the pushed steps so they are attempted at most once per launch.
  bool _followUpStarted = false;

  /// Keeps Home out of the tree for the frame before the first session is
  /// pushed over it.
  bool _holdHome = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final onboarding = context.read<OnboardingService>();
    final placement = context.read<PlacementService>();
    var stage = OnboardingStage.completed;
    try {
      stage = await onboarding.resolveStage();
      if (stage == OnboardingStage.placementInProgress &&
          !await placement.isRequired()) {
        // Nothing left to place: don't hold the user on a test with no
        // questions.
        stage = await onboarding.advanceTo(OnboardingStage.placementCompleted);
      }
    } catch (_) {
      // Never let a storage failure lock the user out of the app.
      stage = OnboardingStage.completed;
    }
    _apply(stage);
  }

  Future<OnboardingStage> _advance(OnboardingStage stage) {
    return context.read<OnboardingService>().advanceTo(stage);
  }

  void _apply(OnboardingStage stage) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _holdHome = stage == OnboardingStage.dailyGoalSelected;
    });
    _startFollowUp();
  }

  Future<void> _getStarted() async {
    _apply(await _advance(OnboardingStage.placementInProgress));
  }

  Future<void> _finishPlacement() async {
    _apply(await _advance(OnboardingStage.placementCompleted));
  }

  Future<void> _selectGoal(DailyGoal goal) async {
    await context.read<OnboardingService>().selectDailyGoal(goal);
    if (!mounted) return;
    _refreshHome();
    _apply(OnboardingStage.dailyGoalSelected);
  }

  /// Today's workload has changed. Deliberately not awaited: a reload also
  /// reschedules the daily reminder, and a slow notification stack must not
  /// hold up the next step.
  void _refreshHome() {
    context.read<HomeController>().load(showLoading: false);
  }

  /// Runs the steps that sit on top of Home: the first session, then the
  /// reminder question.
  void _startFollowUp() {
    final stage = _stage;
    if (_followUpStarted ||
        stage == null ||
        stage == OnboardingStage.completed ||
        !stage.isAtLeast(OnboardingStage.dailyGoalSelected)) {
      return;
    }
    _followUpStarted = true;
    _runFollowUp();
  }

  Future<void> _runFollowUp() async {
    try {
      if (_stage == OnboardingStage.dailyGoalSelected) {
        final cards = await _firstSessionCards();
        if (!mounted) return;

        if (cards.isNotEmpty) {
          await _pushFirstSession(cards);
          // The rest of the flow continues from the completion screen.
          return;
        }

        // Nothing is due and nothing new is left, so there is no first
        // session to run. Treat it as done instead of asking every launch.
        _apply(await _advance(OnboardingStage.firstSessionCompleted));
      }

      await _finishOnboarding();
    } catch (_) {
      // Whatever goes wrong, the user ends up in the app rather than in
      // front of a spinner.
      if (mounted) setState(() => _holdHome = false);
    }
  }

  Future<List<KanjiCard>> _firstSessionCards() async {
    try {
      return await context.read<HomeController>().cardsForSession();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _pushFirstSession(List<KanjiCard> cards) async {
    final home = context.read<HomeController>();
    final route = AppRoutes.session<void>(
      context,
      ReviewScreen(
        cards: cards,
        config: home.config,
        onSessionComplete: (summary, startOfDay) => FirstSessionCompleteScreen(
          summary: summary,
          startOfDay: startOfDay,
          onContinue: _afterFirstSession,
        ),
      ),
    );

    final pushed = Navigator.of(context).push(route);
    // Home can come back now: the session covers it.
    setState(() => _holdHome = false);
    await pushed;
    if (mounted) _refreshHome();
  }

  /// Leaves the completion screen, then asks about reminders.
  Future<void> _afterFirstSession() async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _refreshHome();
    _apply(await _advance(OnboardingStage.firstSessionCompleted));
    if (!mounted) return;
    await _finishOnboarding();
  }

  Future<void> _finishOnboarding() async {
    if (!mounted) return;
    await _askAboutReminders();
    if (!mounted) return;
    _apply(await _advance(OnboardingStage.completed));
  }

  /// Only worth asking when the OS has something left to grant.
  Future<void> _askAboutReminders() async {
    final scheduler = context.read<ReminderScheduler?>();
    if (scheduler == null) return;

    try {
      if (await scheduler.permission() == NotificationPermission.granted) {
        return;
      }
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final navigator = Navigator.of(context);
    await navigator.push(
      AppRoutes.session<void>(
        context,
        ReminderPromptScreen(onDone: () => navigator.maybePop()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    if (stage == null || _holdHome) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return switch (stage) {
      OnboardingStage.notStarted => WelcomeScreen(onGetStarted: _getStarted),
      OnboardingStage.placementInProgress => PlacementScreen(
        onFinished: _finishPlacement,
      ),
      OnboardingStage.placementCompleted => DailyGoalScreen(
        onSelected: _selectGoal,
      ),
      OnboardingStage.dailyGoalSelected ||
      OnboardingStage.firstSessionCompleted ||
      OnboardingStage.completed => const HomeScreen(),
    };
  }
}
