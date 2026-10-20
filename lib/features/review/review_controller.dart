import 'package:flutter/foundation.dart';

import '../../core/models/card_schedule.dart';
import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/progress.dart';
import '../../core/models/start_of_day.dart';
import '../../core/models/review.dart';
import '../../core/models/review_duration.dart';
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
  bool _acceptedExtraTime = false;
  bool _holdingForContinue = false;
  bool _reviewTimeReady = false;
  bool _deferredReviewTimeSave = false;
  Future<void> _reviewTimeWrites = Future<void>.value();
  StartOfDay _startOfDay = StartOfDay.defaults;
  final List<_AnswerUndo> _undo = [];
  bool _shakeHintLoaded = false;
  bool _shakeHintSeen = false;
  bool _shakeHintArmed = false;

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
    if (_holdingForContinue) return;
    final now = clock();
    reviewClock.resume(now);
    _cardTimer.resume(now);
  }

  /// Starts the extra cards after the learner chooses Continue.
  ///
  /// Returns the final summary when nothing is left to study. A null return
  /// means the next card is ready.
  Future<SessionSummary?> continuePastAllotment() async {
    if (summary?.canContinue != true || busy || _disposed) return summary;
    _acceptedExtraTime = true;
    _holdingForContinue = false;
    busy = true;
    _visibleCard = null;
    notifyListeners();

    final now = clock();
    resumeReviewTime();
    try {
      if (await _continueForTimeGoal(now)) {
        summary = null;
        _visibleCard = session.current;
        _resetForNextCard();
        return null;
      }
      final dayBoundary = await _loadStartOfDay();
      return _closeSession(now, dayBoundary);
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
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
        return _closeSession(now, dayBoundary);
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
        return _closeSession(now, dayBoundary);
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
      final previousSchedule = await progressRepository.getSchedule(card.id);
      final previousPace = await progressRepository.getReviewDurationModel();
      if (!isPractice) {
        final existing = previousSchedule ?? CardSchedule.fresh(card.id, now);
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

      final historyEntry = ReviewHistoryEntry(
        cardId: card.id,
        rating: result,
        timestamp: now,
        timeOnCard: timeOnCard,
        isPractice: isPractice,
      );
      await progressRepository.addHistory(historyEntry);

      final beforeAnswer = session.checkpoint();
      session.recordRating(result);
      if (!isPractice) {
        _offerDueCards(now);
      }
      _visibleCard = session.current ?? card;

      if (session.isComplete && await _continueForTimeGoal(now)) {
        _visibleCard = session.current ?? card;
      }

      if (session.isComplete) {
        summary = await _closeSession(now, dayBoundary);
        busy = false;
        notifyListeners();
        return summary;
      }

      _undo.add(
        _AnswerUndo(
          session: beforeAnswer,
          cardId: card.id,
          schedule: previousSchedule,
          hadSchedule: previousSchedule != null,
          pace: previousPace,
          historyEntry: historyEntry,
          drawing: drawing,
          answer: answer,
          suggestedResult: suggestedResult,
          phase: phase,
        ),
      );
      _resetForNextCard();
      await _noteAnswerForShakeHint();
    } finally {
      busy = false;
      notifyListeners();
    }

    return null;
  }

  /// Reverses the most recent Again or Good, including its saved schedule.
  ///
  /// Returns false when there is nothing to undo, an answer is still being
  /// saved, or the sitting has already ended.
  Future<bool> undoLastAnswer() async {
    if (_disposed || busy || !ready || session.isComplete || _undo.isEmpty) {
      return false;
    }

    busy = true;
    final snapshot = _undo.removeLast();
    notifyListeners();

    try {
      if (snapshot.hadSchedule && snapshot.schedule != null) {
        await progressRepository.saveSchedule(snapshot.schedule!);
      } else {
        await progressRepository.deleteSchedule(snapshot.cardId);
      }
      await progressRepository.saveReviewDurationModel(snapshot.pace);
      await progressRepository.removeLastHistory(snapshot.historyEntry);
      if (_disposed) return true;
      _restoreAnsweredCard(snapshot);
      return true;
    } catch (_) {
      _undo.add(snapshot);
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// True once, after the first answer that left the sitting in progress.
  ///
  /// The hint is stored as seen before this returns, so a later launch does
  /// not show it again.
  bool takeShakeUndoHint() {
    if (!_shakeHintArmed) return false;
    _shakeHintArmed = false;
    return true;
  }

  Future<void> _noteAnswerForShakeHint() async {
    if (_shakeHintSeen || _disposed) return;
    if (!_shakeHintLoaded) {
      try {
        final seen = await progressRepository.hasSeenShakeUndoHint();
        if (!_shakeHintSeen) _shakeHintSeen = seen;
      } catch (_) {}
      _shakeHintLoaded = true;
    }
    if (_shakeHintSeen || _disposed || session.isComplete) return;
    _shakeHintSeen = true;
    _shakeHintArmed = true;
    try {
      await progressRepository.markShakeUndoHintSeen();
    } catch (_) {}
  }

  void _restoreAnsweredCard(_AnswerUndo snapshot) {
    session.restore(snapshot.session);
    if (snapshot.hadSchedule && snapshot.schedule != null) {
      _schedules[snapshot.cardId] = snapshot.schedule!;
    } else {
      _schedules.remove(snapshot.cardId);
    }
    _visibleCard = session.current;
    drawing = snapshot.drawing;
    answer = snapshot.answer;
    suggestedResult = snapshot.suggestedResult;
    phase = snapshot.phase;
    padGeneration++;
    summary = null;
    _holdingForContinue = false;
    _beginCardTiming();
  }

  Future<SessionSummary> _closeSession(
    DateTime now,
    StartOfDay dayBoundary,
  ) async {
    _undo.clear();
    final offerContinue = await _canOfferContinue(now);
    if (offerContinue) {
      _holdingForContinue = true;
      reviewClock.pause(now);
      _cardTimer.pause(now);
    }
    await _recordFinishedSession(now, dayBoundary);
    final base = await _summarize(now);
    summary = SessionSummary(
      duration: base.duration,
      reviewedCount: base.reviewedCount,
      successfulCount: base.successfulCount,
      againCount: base.againCount,
      nextReviewAt: base.nextReviewAt,
      canContinue: offerContinue,
    );
    return summary!;
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

  /// After Continue, pull the next priority card while today's goal is ahead.
  ///
  /// Checked only between cards, using [reviewClock], so the current card is
  /// never cut off and background time stays uncounted.
  Future<bool> _continueForTimeGoal(DateTime now) async {
    if (!_acceptedExtraTime) return false;
    final next = await _nextContinuationCard(now);
    if (next == null) return false;
    return session.continueWith(next);
  }

  Future<bool> _canOfferContinue(DateTime now) async {
    if (_acceptedExtraTime) return false;
    return await _nextContinuationCard(now) != null;
  }

  Future<KanjiCard?> _nextContinuationCard(DateTime now) async {
    final workload = workloadService;
    if (workload == null || isPractice || isStudyAnyway || _disposed) {
      return null;
    }
    if (!_reviewTimeReady) await hydrate();
    if (_disposed || !session.isComplete) return null;

    final settings = await progressRepository.getSettings();
    _startOfDay = settings.startOfDay;
    reviewClock.startOfDay = _startOfDay;
    final goal = Duration(minutes: settings.dailyStudyMinutes);
    if (reviewClock.totalAt(now) >= goal) return null;

    final ranked = await workload.eligibleByPriority(now: now);
    if (_disposed || !session.isComplete) return null;
    final latest = await progressRepository.getSchedules();
    _schedules.addAll(latest);

    for (final card in ranked) {
      if (!_canContinueWith(card, now)) continue;
      return card;
    }
    return null;
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

/// One committed Again or Good, and the state from just before it.
class _AnswerUndo {
  const _AnswerUndo({
    required this.session,
    required this.cardId,
    required this.schedule,
    required this.hadSchedule,
    required this.pace,
    required this.historyEntry,
    required this.drawing,
    required this.answer,
    required this.suggestedResult,
    required this.phase,
  });

  final ReviewSessionCheckpoint session;
  final String cardId;
  final CardSchedule? schedule;
  final bool hadSchedule;
  final ReviewDurationModel pace;
  final ReviewHistoryEntry historyEntry;
  final HandwritingInput drawing;
  final ReviewAnswer? answer;
  final ReviewResult? suggestedResult;
  final StudyPhase phase;
}
