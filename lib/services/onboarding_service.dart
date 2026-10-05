import '../core/models/daily_goal.dart';
import '../core/models/onboarding.dart';
import '../core/models/progress.dart';
import '../repositories/progress_repository.dart';
import 'daily_workload_estimator.dart';

/// Owns where the user is in the first-launch flow.
///
/// Reads and writes the app's existing progress store; the stage is the only
/// new state, and it never moves backwards.
class OnboardingService {
  OnboardingService({
    required this.progressRepository,
    this.estimator = const DailyWorkloadEstimator(),
  });

  final ProgressRepository progressRepository;
  final DailyWorkloadEstimator estimator;

  Future<OnboardingProgress> progress() => progressRepository.getOnboarding();

  /// The stage to resume at, reconciled with what the rest of the app already
  /// knows.
  ///
  /// Installs that predate onboarding have no stage recorded, so a completed
  /// placement test or a single finished session is read as "already past it".
  /// A failure here sends the user to the normal app rather than trapping them
  /// in a flow we cannot persist.
  Future<OnboardingStage> resolveStage() async {
    try {
      final onboarding = await progressRepository.getOnboarding();
      if (onboarding.isComplete) return OnboardingStage.completed;

      final hasStudied =
          (await progressRepository.getStreak()).lastStudyDate != null;

      if (onboarding.stage == OnboardingStage.notStarted) {
        final placed = (await progressRepository.getPlacement()).completed;
        if (placed || hasStudied) {
          return _save(onboarding.atLeast(OnboardingStage.completed));
        }
        return OnboardingStage.notStarted;
      }

      // A session finished outside the onboarding flow still counts as the
      // first one: there is no second Day 1.
      if (hasStudied &&
          !onboarding.stage.isAtLeast(OnboardingStage.firstSessionCompleted)) {
        return _save(onboarding.atLeast(OnboardingStage.firstSessionCompleted));
      }

      return onboarding.stage;
    } catch (_) {
      return OnboardingStage.completed;
    }
  }

  Future<OnboardingStage> advanceTo(OnboardingStage stage) async {
    final onboarding = await progressRepository.getOnboarding();
    return _save(onboarding.atLeast(stage));
  }

  /// Records the time budget and the daily new-kanji allowance it implies.
  Future<void> selectDailyGoal(DailyGoal goal) async {
    final settings = await progressRepository.getSettings();
    await progressRepository.saveSettings(
      settings.copyWith(
        newKanjiPerDay: newKanjiPerDayFor(goal, settings),
        dailyStudyMinutes: goal.minutes,
      ),
    );
    await advanceTo(OnboardingStage.dailyGoalSelected);
  }

  /// The largest daily allowance whose estimated time still fits [goal].
  ///
  /// Uses the same estimator Settings shows, so the goal and the number the
  /// user sees later cannot drift apart.
  int newKanjiPerDayFor(DailyGoal goal, [AppSettings? settings]) {
    final seconds = (settings ?? const AppSettings()).averageSecondsPerCard;
    var result = 1;
    for (var count = 1; count <= AppSettings.maxNewKanjiPerDay; count++) {
      final estimate = estimator.estimate(
        newKanjiPerDay: count,
        averageSecondsPerCard: seconds,
      );
      if (estimate.minMinutes > goal.minutes) break;
      result = count;
    }
    return result;
  }

  Future<bool> hasSeenHint(OnboardingHint hint) async {
    try {
      return (await progressRepository.getOnboarding()).hasSeen(hint);
    } catch (_) {
      return true;
    }
  }

  Future<void> markHintSeen(OnboardingHint hint) => markHintsSeen([hint]);

  /// Stored in one write: two hints marked separately can overwrite each
  /// other, since the whole record is saved at once.
  Future<void> markHintsSeen(Iterable<OnboardingHint> hints) async {
    try {
      final onboarding = await progressRepository.getOnboarding();
      var next = onboarding;
      for (final hint in hints) {
        next = next.withHintSeen(hint);
      }
      if (next.seenHints.length == onboarding.seenHints.length) return;
      await progressRepository.saveOnboarding(next);
    } catch (_) {
      // A hint that cannot be remembered is not worth an error.
    }
  }

  Future<OnboardingStage> _save(OnboardingProgress next) async {
    await progressRepository.saveOnboarding(next);
    return next.stage;
  }
}
