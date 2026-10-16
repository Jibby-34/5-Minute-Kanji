import 'package:flutter/foundation.dart';

import '../../core/models/card_schedule.dart';
import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/progress.dart';
import '../../core/models/start_of_day.dart';
import '../../core/models/review.dart';
import '../../core/models/study_phase.dart';
import '../../core/utils/clock.dart';
import '../../repositories/progress_repository.dart';
import '../../services/active_duration_timer.dart';
import '../../services/answer_grader.dart';
import '../../services/card_time_estimator.dart';
import '../../services/daily_review_clock.dart';
import '../../services/daily_workload.dart';
import '../../services/due_card_selector.dart';
import '../../services/kanji_status_resolver.dart';
import '../../services/mark_as_known.dart';
import '../../services/review_session.dart';
import '../../services/srs_scheduler.dart';
import '../../services/streak_service.dart';

class ReviewController extends ChangeNotifier {
  ReviewController({
    required this.progressRepository,
    required this.srsEngine,
    required List<KanjiCard> cards,
    required ReviewSessionConfig config,
    this.isPractice = false,
    this.isStudyAnyway = false,
    this.streakService = const StreakService(),
    this.grader = const ManualAnswerGrader(),
    this.statusResolver = const KanjiStatusResolver(),
    this.selector = const DueCardSelector(),
    this.timeEstimator = const CardTimeEstimator(),
    this.workloadService,
    MarkAsKnownService? markAsKnown,
    Map<String, CardSchedule>? schedules,
    DateTime? startTime,
    Clock? clock,
  }) : clock = clock ?? DateTime.now,
       markAsKnown =
           markAsKnown ??
           MarkAsKnownService(
             progressRepository: progressRepository,
             srsEngine: srsEngine,
             clock: clock,
           ),
       session = ReviewSession(
         config: config,
         cards: cards,
         isPractice: isPractice,
         startTime: startTime ?? (clock ?? DateTime.now)(),
       ) {
    reviewClock = DailyReviewClock(
      startedAt: session.startTime,
      startOfDay: _startOfDay,
    );
    if (schedules != null) {
      _schedules = Map<String, CardSchedule>.from(schedules);
      _applyPhaseForCurrent();
      ready = true;
      _beginCardTiming();
    }
  }

  final ProgressRepository progressRepository;
  final SrsScheduler srsEngine;
  final MarkAsKnownService markAsKnown;
  final Clock clock;
  final StreakService streakService;
  final AnswerGrader grader;
  final KanjiStatusResolver statusResolver;
  final DueCardSelector selector;
  final CardTimeEstimator timeEstimator;

  /// When set, an unfinished daily time goal can draw the next priority card.
  final DailyWorkloadService? workloadService;
  final bool isPractice;
  final bool isStudyAnyway;
  final ReviewSession session;
  late final DailyReviewClock reviewClock;

  bool ready = false;
  bool busy = false;
  StudyPhase phase = StudyPhase.recall;
  HandwritingInput drawing = HandwritingInput.empty;
  ReviewAnswer? answer;
  ReviewResult? suggestedResult;
  final ActiveDurationTimer _cardTimer = ActiveDurationTimer();
  bool _cardTimingOpen = false;
  SessionSummary? summary;
  KanjiCard? _visibleCard;
  Map<String, CardSchedule> _schedules = {};
  int padGeneration = 0;
  bool _disposed = false;
  bool _reviewTimeReady = false;
  bool _deferredReviewTimeSave = false;
  Future<void> _reviewTimeWrites = Future<void>.value();
  StartOfDay _startOfDay = StartOfDay.defaults;

  KanjiCard? get current => session.current ?? _visibleCard;

  bool get isComplete => session.isComplete;

  StartOfDay get startOfDay => _startOfDay;

  /// Cards still left to draw: queued items, plus the first retrieval each
  /// unlearned card will add later in the sitting.
  int get remainingToDraw {
    var count = session.remaining;
    if (!isPractice) {
      for (final card in session.queued) {
        if (_needsLearn(card)) count++;
      }
    }
    if (phase == StudyPhase.compare && count > 0) count--;
    return count;
  }

  bool get submitted => phase == StudyPhase.compare;

  Future<void> hydrate() async {
    if (_disposed || _reviewTimeReady) return;
    final settings = await progressRepository.getSettings();
    if (_reviewTimeReady) return;
    if (_disposed && !_deferredReviewTimeSave) return;
    _startOfDay = settings.startOfDay;
    reviewClock.startOfDay = _startOfDay;

    final stored = await progressRepository.getDailyReviewTime();
    if (_reviewTimeReady) return;
    if (_disposed && !_deferredReviewTimeSave) return;
    final normalized = stored.forDay(clock(), startOfDay: _startOfDay);
    reviewClock.accrued = normalized.duration;
    reviewClock.accruedDay = normalized.date;
    _reviewTimeReady = true;

    if (!_disposed && !ready) {
      final schedules = await progressRepository.getSchedules();
      if (!_disposed && !ready) {
        _schedules = Map<String, CardSchedule>.from(schedules);
        _applyPhaseForCurrent();
        ready = true;
        _beginCardTiming();
      }
    }

    if (_deferredReviewTimeSave) await checkpointReviewTime();
    if (!_disposed) notifyListeners();
  }

  /// Freezes the daily clock. Time until the app is open again is not review.
  void pauseReviewTime() {
    final now = clock();
    reviewClock.pause(now);
    _cardTimer.pause(now);
  }

  /// Continues the daily clock from [clock], leaving the gap uncounted.
  void resumeReviewTime() {
    final now = clock();
    reviewClock.resume(now);
    _cardTimer.resume(now);
  }

  /// Writes today's review time. Safe to call again; each save replaces the
  /// day's total with the clock's current value.
  Future<void> checkpointReviewTime([DateTime? at]) {
    if (!_reviewTimeReady) {
      _deferredReviewTimeSave = true;
      return Future<void>.value();
    }
    _deferredReviewTimeSave = false;
    final now = at ?? clock();
    final snapshot = DailyReviewTime(
      date: _startOfDay.studyDate(now),
      duration: reviewClock.totalAt(now),
    );
    final run = _reviewTimeWrites.then(
      (_) => progressRepository.saveDailyReviewTime(snapshot),
    );
    _reviewTimeWrites = run.catchError((Object _) {});
    return run;
  }

  Future<StartOfDay> _loadStartOfDay() async {
    final settings = await progressRepository.getSettings();
    _startOfDay = settings.startOfDay;
    reviewClock.startOfDay = _startOfDay;
    return _startOfDay;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void updateDrawing(HandwritingInput next) {
    if (phase != StudyPhase.practice && phase != StudyPhase.recall) return;
    drawing = next;
  }

  void clearDrawing() {
    if (phase != StudyPhase.practice && phase != StudyPhase.recall) return;
    drawing = HandwritingInput.empty;
    padGeneration++;
    notifyListeners();
  }

  void beginPractice() {
    if (!ready || phase != StudyPhase.learn || busy) return;
    drawing = HandwritingInput.empty;
    padGeneration++;
    phase = StudyPhase.practice;
    notifyListeners();
  }

  Future<SessionSummary?> completePractice() async {
    if (!ready || phase != StudyPhase.practice || busy) return null;
    final card = current;
    if (card == null) return null;

    if (isPractice) {
      drawing = HandwritingInput.empty;
      padGeneration++;
      phase = StudyPhase.recall;
      notifyListeners();
      return null;
    }

    busy = true;
    notifyListeners();

    final now = clock();
    final active = _cardTimer.elapsedAt(now);
    try {
      final dayBoundary = await _loadStartOfDay();
      final existing =
          await progressRepository.getSchedule(card.id) ??
          CardSchedule.fresh(card.id, now);
      final updated = srsEngine.introduce(current: existing, now: now);
      await progressRepository.saveSchedule(updated);
      _schedules[card.id] = updated;
      if (existing.state == CardLearningState.newCard) {
        await _recordPace(schedule: existing, isNew: true, duration: active);
        final daily = (await progressRepository.getDailyNewKanji()).forDay(
          now,
          startOfDay: dayBoundary,
        );
        await progressRepository.saveDailyNewKanji(daily.increment());
      }

      session.completeIntroduction();
      _offerDueCards(now);
      _visibleCard = session.current ?? card;

      if (session.isComplete && await _continueForTimeGoal(now)) {
        _visibleCard = session.current ?? card;
      }

      if (session.isComplete) {
        await _recordFinishedSession(now, dayBoundary);
        summary = await _summarize(now);
        return summary;
      }

      _resetForNextCard();
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<SessionSummary?> markCurrentAsKnown() async {
    if (!ready || phase != StudyPhase.learn || busy || isPractice) return null;
    final card = current;
    if (card == null) return null;

    busy = true;
    notifyListeners();

    final now = clock();
    try {
      final dayBoundary = await _loadStartOfDay();
      final updated = await markAsKnown.markKanjiAsKnown(card.id, now: now);
      if (updated != null) {
        _schedules[card.id] = updated;
      }

      session.completeIntroduction();
      _offerDueCards(now);
      _visibleCard = session.current ?? card;

      if (session.isComplete && await _continueForTimeGoal(now)) {
        _visibleCard = session.current ?? card;
      }

      if (session.isComplete) {
        await _recordFinishedSession(now, dayBoundary);
        summary = await _summarize(now);
        return summary;
      }

      _resetForNextCard();
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void submit() {
    final card = current;
    if (!ready || card == null || phase != StudyPhase.recall || busy) return;

    answer = ReviewAnswer(
      cardId: card.id,
      drawing: drawing,
      submittedAt: DateTime.now(),
    );
    suggestedResult = grader.suggest(answer!, card);
    phase = StudyPhase.compare;
    notifyListeners();
  }

  Future<SessionSummary?> rate(ReviewResult result) async {
    final card = current;
    if (!ready || card == null || phase != StudyPhase.compare || busy) {
      return null;
    }

    busy = true;
    notifyListeners();

    final now = clock();
    final timeOnCard = _cardTimer.elapsedAt(now);

    try {
      final dayBoundary = await _loadStartOfDay();
      if (!isPractice) {
        final existing =
            await progressRepository.getSchedule(card.id) ??
            CardSchedule.fresh(card.id, now);
        final updated = srsEngine.schedule(
          current: existing,
          result: result,
          now: now,
        );
        await progressRepository.saveSchedule(updated);
        _schedules[card.id] = updated;
        await _recordPace(
          schedule: existing,
          isNew: false,
          duration: timeOnCard,
        );
      }

      await progressRepository.addHistory(
        ReviewHistoryEntry(
          cardId: card.id,
          rating: result,
          timestamp: now,
          timeOnCard: timeOnCard,
          isPractice: isPractice,
        ),
      );

      session.recordRating(result);
      if (!isPractice) {
        _offerDueCards(now);
      }
      _visibleCard = session.current ?? card;

      if (session.isComplete && await _continueForTimeGoal(now)) {
        _visibleCard = session.current ?? card;
      }

      if (session.isComplete) {
        await _recordFinishedSession(now, dayBoundary);
        summary = await _summarize(now);
        busy = false;
        notifyListeners();
        return summary;
      }

      _resetForNextCard();
    } finally {
      busy = false;
      notifyListeners();
    }

    return null;
  }

  Future<SessionSummary> _summarize(DateTime now) async {
    await checkpointReviewTime(now);
    return session.toSummary(
      now: now,
      nextReviewAt: await _soonestDue(now),
      duration: reviewClock.totalAt(now),
    );
  }

  Future<void> _recordFinishedSession(
    DateTime now,
    StartOfDay dayBoundary,
  ) async {
    final streak = await progressRepository.getStreak();
    await progressRepository.saveStreak(
      streakService.recordCompletion(streak, now, startOfDay: dayBoundary),
    );
    if (isPractice || isStudyAnyway) return;

    final settings = await progressRepository.getSettings();
    final plan = await progressRepository.getDailySessionPlan();
    final today = settings.startOfDay.studyDate(now);
    if (!plan.matches(
      studyDate: today,
      budgetMinutes: settings.dailyStudyMinutes,
      newKanjiPerDay: settings.newKanjiPerDay,
      startOfDay: settings.startOfDay,
      curriculumMode: settings.curriculumMode,
    )) {
      return;
    }
    if (plan.completed) return;
    await progressRepository.saveDailySessionPlan(
      plan.copyWith(completed: true),
    );
  }

  bool _needsLearn(KanjiCard card) {
    if (session.hasReviewed(card.id)) return false;
    final schedule = _schedules[card.id];
    return schedule == null || schedule.state == CardLearningState.newCard;
  }

  /// When the allotted queue is empty, pull the next priority card if today's
  /// study-time goal is still ahead and another eligible card remains.
  ///
  /// Checked only between cards, using [reviewClock], so the current card is
  /// never cut off and background time stays uncounted.
  Future<bool> _continueForTimeGoal(DateTime now) async {
    final workload = workloadService;
    if (workload == null || isPractice || isStudyAnyway || _disposed) {
      return false;
    }
    if (!_reviewTimeReady) await hydrate();
    if (_disposed || !session.isComplete) return false;

    final settings = await progressRepository.getSettings();
    _startOfDay = settings.startOfDay;
    reviewClock.startOfDay = _startOfDay;
    final goal = Duration(minutes: settings.dailyStudyMinutes);
    if (reviewClock.totalAt(now) >= goal) return false;

    final ranked = await workload.eligibleByPriority(now: now);
    if (_disposed || !session.isComplete) return false;
    final latest = await progressRepository.getSchedules();
    _schedules.addAll(latest);

    for (final card in ranked) {
      if (!_canContinueWith(card, now)) continue;
      if (session.continueWith(card)) return true;
    }
    return false;
  }

  bool _canContinueWith(KanjiCard card, DateTime now) {
    if (session.hasReviewed(card.id)) return false;
    if (session.queued.any((queued) => queued.id == card.id)) return false;
    if (session.pool.any((pooled) => pooled.id == card.id)) return false;
    return selector.isDue(_schedules[card.id], now, startOfDay: _startOfDay);
  }

  void _offerDueCards(DateTime now) {
    final due = selector.select(
      cards: session.pool,
      schedules: _schedules,
      now: now,
      limit: session.pool.length,
      maxNewCards: 0,
      startOfDay: _startOfDay,
    );
    session.offerDue(due);
    if (!session.isComplete) return;

    // A sitting must not report done while pooled new kanji are still
    // unlearned — including the 0-review case where the queue is only news.
    final unlearned = session.pool.where(_needsLearn).toList();
    if (unlearned.isNotEmpty) {
      session.offerDue(unlearned);
    }
  }

  void _applyPhaseForCurrent() {
    final card = current;
    if (card == null) return;
    phase = _needsLearn(card) ? StudyPhase.learn : StudyPhase.recall;
  }

  void _beginCardTiming() {
    final now = clock();
    _cardTimer.start(now);
    _cardTimingOpen = true;
    if (!reviewClock.isRunning) _cardTimer.pause(now);
  }

  /// One finished card updates the pace model once. A repeat of the same
  /// showing finds the timer closed and is ignored.
  Future<void> _recordPace({
    required CardSchedule? schedule,
    required bool isNew,
    required Duration duration,
  }) async {
    final active = _cardTimingOpen ? duration : Duration.zero;
    _cardTimingOpen = false;
    if (!CardTimeEstimator.isUsableDuration(active)) return;
    final current = await progressRepository.getReviewDurationModel();
    final next = timeEstimator.learn(
      current,
      schedule: schedule,
      isNew: isNew,
      duration: active,
    );
    if (next == null) return;
    await progressRepository.saveReviewDurationModel(next);
  }

  void _resetForNextCard() {
    drawing = HandwritingInput.empty;
    answer = null;
    suggestedResult = null;
    padGeneration++;
    _beginCardTiming();
    _applyPhaseForCurrent();
  }

  Future<DateTime?> _soonestDue(DateTime now) async {
    final schedules = await progressRepository.getSchedules();
    DateTime? next;
    for (final schedule in schedules.values) {
      if (schedule.isDueAt(now)) continue;
      if (next == null || schedule.dueAt.isBefore(next)) {
        next = schedule.dueAt;
      }
    }
    return next;
  }
}
