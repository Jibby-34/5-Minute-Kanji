import 'dart:math' as math;

import '../core/models/card_schedule.dart';
import '../core/models/daily_session_plan.dart';
import '../core/models/kanji_card.dart';
import '../core/models/progress.dart';
import '../core/models/start_of_day.dart';
import '../repositories/kanji_repository.dart';
import '../repositories/progress_repository.dart';
import 'card_priority_scorer.dart';
import 'card_time_estimator.dart';
import 'due_card_selector.dart';
import 'session_planner.dart';

/// One reading of what is left in the current study day.
///
/// The Home screen and the daily reminder both render this snapshot, so the
/// two can never disagree about the day's workload. [sessionCards] is the
/// time-budgeted recommendation, not every eligible card.
class DailyWorkload {
  const DailyWorkload({
    required this.dueCount,
    required this.newRemainingToday,
    required this.estimatedMinutes,
    required this.startOfDay,
    this.nextReviewAt,
    this.sessionCards = const [],
    this.overflowCards = const [],
    this.recommendedComplete = false,
    this.plannedRemaining,
  });

  static const empty = DailyWorkload(
    dueCount: 0,
    newRemainingToday: 0,
    estimatedMinutes: 0,
    startOfDay: StartOfDay.defaults,
  );

  final int dueCount;

  /// New kanji still left in today's allowance.
  final int newRemainingToday;

  /// Home's `~n min` estimate for the recommended sitting.
  final int estimatedMinutes;

  final StartOfDay startOfDay;
  final DateTime? nextReviewAt;

  /// Cards the normal sitting would draw from.
  final List<KanjiCard> sessionCards;

  /// Eligible cards that did not fit the normal sitting, priority order.
  ///
  /// Empty until the recommended sitting is finished.
  final List<KanjiCard> overflowCards;

  /// The user finished today's recommended sitting.
  final bool recommendedComplete;

  /// When set, Home and reminders count the planned sitting rather than
  /// every due or new card. Null keeps the older count for callers that
  /// build a workload by hand.
  final int? plannedRemaining;

  bool get isCaughtUp => dueCount == 0 && newRemainingToday == 0;

  bool get studyAnywayAvailable =>
      recommendedComplete && overflowCards.isNotEmpty;

  bool get usesPlannedSession =>
      recommendedComplete || plannedRemaining != null;

  /// True when the headline count refers to new kanji rather than reviews.
  /// Mirrors how Home picks its wording for workloads built without a plan.
  bool get countsNewKanji => newRemainingToday > 0;

  /// The number Home and the reminder treat as today's work.
  int get remainingCount {
    if (recommendedComplete) return 0;
    if (plannedRemaining != null) return plannedRemaining!;
    return countsNewKanji ? newRemainingToday : dueCount;
  }
}

/// Computes the day's workload from progress + settings.
///
/// SRS still decides what is eligible. This service only chooses which of
/// those cards fit the user's time budget.
class DailyWorkloadService {
  const DailyWorkloadService({
    required this.kanjiRepository,
    required this.progressRepository,
    this.selector = const DueCardSelector(),
    this.scorer = const CardPriorityScorer(),
    this.timeEstimator = const CardTimeEstimator(),
    this.planner = const SessionPlanner(),
  });

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final DueCardSelector selector;
  final CardPriorityScorer scorer;
  final CardTimeEstimator timeEstimator;
  final SessionPlanner planner;

  Future<DailyWorkload> read({required DateTime now}) async {
    final cards = await kanjiRepository.getAll();
    final schedules = await progressRepository.getSchedules();
    final settings = await progressRepository.getSettings();
    final dayBoundary = settings.startOfDay;
    final daily = (await progressRepository.getDailyNewKanji()).forDay(
      now,
      startOfDay: dayBoundary,
    );
    final remainingDaily = daily.remainingAllowance(settings.newKanjiPerDay);
    final unencountered = selector.countNew(cards: cards, schedules: schedules);
    final due = selector.countDue(
      cards: cards,
      schedules: schedules,
      now: now,
      startOfDay: dayBoundary,
    );
    final remainingNew = math.min(unencountered, remainingDaily);
    final candidates = _candidates(
      cards: cards,
      schedules: schedules,
      now: now,
      startOfDay: dayBoundary,
      maxNewCards: remainingNew,
    );
    final studyDate = dayBoundary.studyDate(now);
    final stored = await progressRepository.getDailySessionPlan();
    final planMatches = stored.matches(
      studyDate: studyDate,
      budgetMinutes: settings.dailyStudyMinutes,
      newKanjiPerDay: settings.newKanjiPerDay,
      startOfDay: dayBoundary,
    );

    final List<KanjiCard> session;
    final List<KanjiCard> overflow;
    final bool complete;
    final Duration estimated;

    if (planMatches) {
      final outstanding = _outstanding(stored, candidates);
      final finished =
          stored.completed ||
          (stored.cardIds.isNotEmpty && outstanding.isEmpty);
      if (finished) {
        complete = true;
        session = const [];
        overflow = _byPriority(candidates);
        estimated = Duration.zero;
        if (!stored.completed) {
          await progressRepository.saveDailySessionPlan(
            stored.copyWith(completed: true),
          );
        }
      } else {
        complete = false;
        session = outstanding;
        overflow = const [];
        estimated = _estimateCards(outstanding, candidates);
      }
    } else {
      final planned = planner.plan(
        candidates: candidates,
        budget: Duration(minutes: settings.dailyStudyMinutes),
        maxNewCards: remainingNew,
      );
      final next = DailySessionPlan(
        studyDate: studyDate,
        budgetMinutes: settings.dailyStudyMinutes,
        newKanjiPerDay: settings.newKanjiPerDay,
        startOfDay: dayBoundary,
        cardIds: planned.selected
            .map((candidate) => candidate.card.id)
            .toList(),
      );
      await progressRepository.saveDailySessionPlan(next);
      complete = false;
      session = planned.selected.map((candidate) => candidate.card).toList();
      overflow = const [];
      estimated = planned.estimated;
    }

    return DailyWorkload(
      dueCount: due,
      newRemainingToday: remainingNew,
      estimatedMinutes: estimatedMinutesFor(estimated),
      startOfDay: dayBoundary,
      nextReviewAt: _nextReviewAt(
        cards: cards,
        schedules: schedules,
        now: now,
        settings: settings,
        dueCount: due,
        unencountered: unencountered,
        remainingNew: remainingNew,
      ),
      sessionCards: session,
      overflowCards: overflow,
      recommendedComplete: complete,
      plannedRemaining: session.length,
    );
  }

  List<SessionCandidate> _candidates({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
    required StartOfDay startOfDay,
    required int maxNewCards,
  }) {
    final news = <KanjiCard>[];
    final existing = <KanjiCard>[];
    for (final card in cards) {
      final schedule = schedules[card.id];
      if (selector.isNew(schedule)) {
        news.add(card);
      } else if (selector.isAvailableToday(
        schedule!,
        now,
        startOfDay: startOfDay,
      )) {
        existing.add(card);
      }
    }
    news.sort(compareKanjiLearnOrder);

    final result = <SessionCandidate>[];
    final newTake = maxNewCards <= 0
        ? const <KanjiCard>[]
        : news.take(maxNewCards);
    for (final card in newTake) {
      result.add(
        _candidate(
          card: card,
          schedule: schedules[card.id],
          now: now,
          isNew: true,
        ),
      );
    }
    for (final card in existing) {
      result.add(
        _candidate(
          card: card,
          schedule: schedules[card.id],
          now: now,
          isNew: false,
        ),
      );
    }
    return result;
  }

  SessionCandidate _candidate({
    required KanjiCard card,
    required CardSchedule? schedule,
    required DateTime now,
    required bool isNew,
  }) {
    return SessionCandidate(
      card: card,
      isNew: isNew,
      priority: scorer.score(
        schedule: schedule,
        now: now,
        isNew: isNew,
        level: card.jlptLevel,
      ),
      estimated: timeEstimator.estimate(schedule, isNew: isNew),
    );
  }

  List<KanjiCard> _outstanding(
    DailySessionPlan plan,
    List<SessionCandidate> candidates,
  ) {
    final byId = {
      for (final candidate in candidates) candidate.card.id: candidate,
    };
    final outstanding = <KanjiCard>[];
    for (final id in plan.cardIds) {
      final candidate = byId[id];
      if (candidate != null) outstanding.add(candidate.card);
    }
    return outstanding;
  }

  List<KanjiCard> _byPriority(List<SessionCandidate> candidates) {
    final ordered = List<SessionCandidate>.from(candidates)
      ..sort((a, b) {
        final byScore = b.priority.compareTo(a.priority);
        if (byScore != 0) return byScore;
        return a.card.id.compareTo(b.card.id);
      });
    return ordered.map((candidate) => candidate.card).toList();
  }

  Duration _estimateCards(
    List<KanjiCard> cards,
    List<SessionCandidate> candidates,
  ) {
    final byId = {
      for (final candidate in candidates) candidate.card.id: candidate,
    };
    var seconds = 0;
    for (final card in cards) {
      seconds += byId[card.id]?.estimated.inSeconds ?? 0;
    }
    return Duration(seconds: seconds);
  }

  DateTime? _nextReviewAt({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
    required AppSettings settings,
    required int dueCount,
    required int unencountered,
    required int remainingNew,
  }) {
    if (dueCount > 0 || remainingNew > 0) return now;

    final nextDue = selector.nextFutureDue(
      cards: cards,
      schedules: schedules,
      now: now,
      startOfDay: settings.startOfDay,
    );

    if (unencountered > 0 && settings.newKanjiPerDay > 0) {
      final tomorrow = settings.startOfDay.startOfNextStudyDay(now);
      if (nextDue == null || tomorrow.isBefore(nextDue)) return tomorrow;
    }
    return nextDue;
  }
}
