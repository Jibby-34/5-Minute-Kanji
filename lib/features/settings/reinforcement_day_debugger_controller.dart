import 'package:flutter/foundation.dart';

import '../../core/models/daily_session_plan.dart';
import '../../core/models/study_allocation.dart';
import '../../core/models/study_day_type.dart';
import '../../core/utils/clock.dart';
import '../../repositories/kanji_repository.dart';
import '../../repositories/progress_repository.dart';
import '../../services/daily_workload.dart';
import '../../services/reinforcement_day.dart';
import '../../services/reinforcement_day_scenarios.dart';

/// How the study-plan preview chooses its day type.
enum DayTypePreview {
  automatic,
  forceNormal,
  forceReinforcement;

  String get label => switch (this) {
    DayTypePreview.automatic => 'Automatic',
    DayTypePreview.forceNormal => 'Force Normal',
    DayTypePreview.forceReinforcement => 'Force Reinforcement',
  };
}

/// The home study-plan card for a preview day type.
///
/// A Reinforcement preview drops new kanji from the sitting already on
/// screen. It does not read or write the saved plan.
StudyAllocation allocationForPreview({
  required StudyAllocation sitting,
  required StudyDayType dayType,
}) {
  if (dayType != StudyDayType.reinforcement) return sitting;
  return StudyAllocation(
    reviewCards: sitting.reviewCards,
    reviewSeconds: sitting.reviewSeconds,
  );
}

/// In-memory threshold tuning for a Reinforcement Day.
///
/// [diagnostic] starts at the production defaults and is never written to
/// settings. [reevaluate] only reads the due queue. [rebuildSavedPlan] is
/// the one write, and it builds today's plan with the production policy.
class ReinforcementDayDebuggerController extends ChangeNotifier {
  ReinforcementDayDebuggerController({
    required this.kanjiRepository,
    required this.progressRepository,
    DailyWorkloadService? workload,
    Clock? clock,
  }) : workload =
           workload ??
           DailyWorkloadService(
             kanjiRepository: kanjiRepository,
             progressRepository: progressRepository,
           ),
       clock = clock ?? DateTime.now;

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;

  /// Reads the live queue. Its day policy stays on the production defaults.
  final DailyWorkloadService workload;
  final Clock clock;

  ReinforcementDayConfig diagnostic = ReinforcementDayConfig.production;
  ReinforcementDiagnosticSource source =
      ReinforcementDiagnosticSource.liveQueue;
  DayTypePreview preview = DayTypePreview.automatic;

  List<double> liveProbabilities = const [];
  DailySessionPlan savedPlan = DailySessionPlan.empty;
  bool loading = true;
  bool rebuilding = false;
  String? rebuildNote;

  int _generation = 0;

  bool get simulation => source.simulation;

  List<double> get activeProbabilities =>
      simulation ? source.probabilities : liveProbabilities;

  ReinforcementDayPolicy get _diagnosticPolicy =>
      ReinforcementDayPolicy(config: diagnostic);

  ReinforcementDayDiagnosis get diagnosis =>
      _diagnosticPolicy.diagnose(activeProbabilities);

  StudyDayType get previewDayType => switch (preview) {
    DayTypePreview.automatic => diagnosis.dayType,
    DayTypePreview.forceNormal => StudyDayType.normal,
    DayTypePreview.forceReinforcement => StudyDayType.reinforcement,
  };

  bool get usingProductionThresholds {
    const shipped = ReinforcementDayConfig.production;
    return diagnostic.minimumDueCards == shipped.minimumDueCards &&
        diagnostic.averageRecallThreshold == shipped.averageRecallThreshold &&
        diagnostic.lowRecallThreshold == shipped.lowRecallThreshold &&
        diagnostic.lowRecallFractionThreshold ==
            shipped.lowRecallFractionThreshold;
  }

  void selectSource(ReinforcementDiagnosticSource next) {
    source = next;
    notifyListeners();
  }

  void selectPreview(DayTypePreview next) {
    preview = next;
    notifyListeners();
  }

  void returnToAutomatic() => selectPreview(DayTypePreview.automatic);

  /// False when [text] is not a whole number from 0 through 999.
  bool applyMinimum(String text) {
    final value = ReinforcementDayConfig.tryParseMinimum(text);
    if (value == null) return false;
    diagnostic = diagnostic.copyWith(minimumDueCards: value);
    notifyListeners();
    return true;
  }

  /// False when [text] is outside 0.0–1.0.
  bool applyAverage(String text) => _applyUnit(
    text,
    (value) => diagnostic.copyWith(averageRecallThreshold: value),
  );

  bool applyLow(String text) => _applyUnit(
    text,
    (value) => diagnostic.copyWith(lowRecallThreshold: value),
  );

  bool applyFraction(String text) => _applyUnit(
    text,
    (value) => diagnostic.copyWith(lowRecallFractionThreshold: value),
  );

  bool _applyUnit(
    String text,
    ReinforcementDayConfig Function(double value) next,
  ) {
    final value = ReinforcementDayConfig.tryParseUnit(text);
    if (value == null) return false;
    diagnostic = next(value);
    notifyListeners();
    return true;
  }

  void resetThresholds() {
    diagnostic = ReinforcementDayConfig.production;
    notifyListeners();
  }

  /// Reads the current due queue and the saved plan again.
  ///
  /// Synthetic scenarios keep their own probabilities. This still refreshes
  /// the live sample and the saved-plan line.
  Future<void> reevaluate() async {
    final generation = ++_generation;
    loading = true;
    notifyListeners();
    try {
      final probabilities = await workload.dueRecallProbabilities(now: clock());
      final plan = await progressRepository.getDailySessionPlan();
      if (generation != _generation) return;
      liveProbabilities = probabilities;
      savedPlan = plan;
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Clears today's saved queue and builds it again with production thresholds.
  ///
  /// Diagnostic values stay on this controller. Schedules, settings, and
  /// trial progress are left alone.
  Future<void> rebuildSavedPlan() async {
    if (rebuilding) return;
    rebuilding = true;
    rebuildNote = null;
    notifyListeners();
    try {
      await progressRepository.saveDailySessionPlan(DailySessionPlan.empty);
      await DailyWorkloadService(
        kanjiRepository: kanjiRepository,
        progressRepository: progressRepository,
      ).read(now: clock());
      rebuildNote =
          "Today's saved plan was built again with the production thresholds.";
    } catch (_) {
      rebuildNote = 'The saved plan could not be rebuilt.';
    } finally {
      rebuilding = false;
      notifyListeners();
    }
    await reevaluate();
  }
}
