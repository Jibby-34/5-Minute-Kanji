import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../core/models/card_schedule.dart';
import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/progress.dart';
import '../../core/models/start_of_day.dart';
import '../../core/models/review.dart';
import '../../core/models/review_duration.dart';
import '../../core/models/study_day_type.dart';
import '../../core/models/study_phase.dart';
import '../../core/utils/clock.dart';
import '../../repositories/progress_repository.dart';
import '../../services/active_duration_timer.dart';
import '../../services/adaptive_session_adjuster.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/analytics/study_review_classification.dart';
import '../../services/answer_grader.dart';
import '../../services/card_priority_scorer.dart';
import '../../services/card_time_estimator.dart';
import '../../services/daily_review_clock.dart';
import '../../services/curriculum/curriculum_access.dart';
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
    this.priorityScorer = const CardPriorityScorer(),
    this.queueAdjuster = const AdaptiveSessionAdjuster(),
    this.extraDueReviews,
    this.workloadService,
    this.curriculumAccess,
    AnalyticsService? analytics,
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
       analytics = analytics ?? AnalyticsService(),
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
      _scheduleSessionStart();
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
  final CardPriorityScorer priorityScorer;

  /// Drops or swaps future reviews when this sitting is running long.
  final AdaptiveSessionAdjuster queueAdjuster;

  /// Due reviews that may replace a longer card. Null loads them from
  /// [workloadService] the first time the sitting runs long.
  final List<KanjiCard>? extraDueReviews;

  /// When set, an unfinished daily time goal can draw the next priority card.
  final DailyWorkloadService? workloadService;

  /// When set, new kanji stop once the free trial is used up.
  final CurriculumAccess? curriculumAccess;
  final AnalyticsService analytics;
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
  final SessionPaceTracker _pace = SessionPaceTracker();
  bool _cardTimingOpen = false;
  SessionSummary? summary;

  /// The latest time the remaining queue was shortened. Null until then.
  AdaptiveQueueDecision? lastQueueAdjustment;
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
  bool _countedStudyDay = false;
  bool _sessionStartScheduled = false;
  bool _sessionStarted = false;
  bool _analyticsFinished = false;
  bool _goalCompleted = false;
  int _newCardsLearned = 0;
  String _sessionType = 'normal';
  Future<void>? _startFuture;
  final Set<String> _introducedIds = {};
  final List<StudyReviewClassification> _pendingReviews = [];

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
      await curriculumAccess?.ensureLoaded();
      if (_disposed) return;
      final schedules = await progressRepository.getSchedules();
      if (!_disposed && !ready) {
        _schedules = Map<String, CardSchedule>.from(schedules);
        ready = true;
        _applyPhaseForCurrent();
        _beginCardTiming();
      }
    }

    if (!_disposed && ready && curriculumAccess != null) {
      await curriculumAccess!.ensureLoaded();
      if (!_disposed) {
        final before = session.remaining;
        _dropBlockedNewCards();
        if (session.remaining != before) {
          _applyPhaseForCurrent();
          if (session.current != null) _beginCardTiming();
        }
      }
    }

    if (_deferredReviewTimeSave) await checkpointReviewTime();
    _scheduleSessionStart();
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
      final wasNew = existing.state == CardLearningState.newCard;
      final access = curriculumAccess;
      var recorded = false;
      if (wasNew && access != null) {
        final decision = await access.tryRecordStudy(card.id);
        if (!decision.allowed) {
          return _skipBlockedNewCard(now, dayBoundary);
        }
        recorded = decision.newlyRecorded;
      }
      final updated = srsEngine.introduce(current: existing, now: now);
      try {
        await progressRepository.saveSchedule(updated);
      } catch (error) {
        if (recorded && access != null) await access.forgetStudy(card.id);
        rethrow;
      }
      _schedules[card.id] = updated;
      final Duration? predicted;
      if (wasNew) {
        _newCardsLearned++;
        _introducedIds.add(card.id);
        predicted = await _recordPace(
          schedule: existing,
          isNew: true,
          duration: active,
        );
        final daily = (await progressRepository.getDailyNewKanji()).forDay(
          now,
          startOfDay: dayBoundary,
        );
        await progressRepository.saveDailyNewKanji(daily.increment());
        await _countStudyDay(now, dayBoundary);
      } else {
        predicted = null;
      }

      session.completeIntroduction();
      _offerDueCards(now);
      if (predicted != null) _pace.record(predicted, active);
      await _adaptAssignedQueue(now);
      _visibleCard = session.current ?? card;

      if (session.isComplete && await _continueForTimeGoal(now)) {
        _visibleCard = session.current ?? card;
      }

      if (session.isComplete) {
        return _closeSession(now, dayBoundary);
      }

      _resetForNextCard();
      if (session.isComplete) return _closeSession(now, dayBoundary);
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
      await _adaptAssignedQueue(now);
      _visibleCard = session.current ?? card;

      if (session.isComplete && await _continueForTimeGoal(now)) {
        _visibleCard = session.current ?? card;
      }

      if (session.isComplete) {
        return _closeSession(now, dayBoundary);
      }

      _resetForNextCard();
      if (session.isComplete) return _closeSession(now, dayBoundary);
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
      final paceBefore = _pace.snapshot();
      final Duration? predicted;
      if (!isPractice) {
        final existing = previousSchedule ?? CardSchedule.fresh(card.id, now);
        final updated = srsEngine.schedule(
          current: existing,
          result: result,
          now: now,
        );
        await progressRepository.saveSchedule(updated);
        _schedules[card.id] = updated;
        predicted = await _recordPace(
          schedule: existing,
          isNew: false,
          duration: timeOnCard,
        );
      } else {
        predicted = null;
      }

      final historyEntry = ReviewHistoryEntry(
        cardId: card.id,
        rating: result,
        timestamp: now,
        timeOnCard: timeOnCard,
        isPractice: isPractice,
      );
      await progressRepository.addHistory(historyEntry);
      await _countStudyDay(now, dayBoundary);

      final beforeAnswer = session.checkpoint();
      session.recordRating(result);
      final classification = isPractice
          ? null
          : classifyStudyReview(
              result: result,
              scheduleBeforeAnswer: previousSchedule,
              introducedThisSession: _introducedIds.contains(card.id),
              now: now,
              startOfDay: dayBoundary,
            );
      if (classification != null) _pendingReviews.add(classification);
      if (!isPractice) {
        _offerDueCards(now);
        if (predicted != null) _pace.record(predicted, timeOnCard);
        await _adaptAssignedQueue(now);
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
          paceTracker: paceBefore,
          historyEntry: historyEntry,
          drawing: drawing,
          answer: answer,
          suggestedResult: suggestedResult,
          phase: phase,
          trackedReview: classification != null,
        ),
      );
      _resetForNextCard();
      if (session.isComplete) {
        summary = await _closeSession(now, dayBoundary);
        return summary;
      }
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
      if (snapshot.trackedReview && _pendingReviews.isNotEmpty) {
        _pendingReviews.removeLast();
      }
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
    _pace.restore(snapshot.paceTracker);
    lastQueueAdjustment = null;
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
    _flushPendingReviews();
    final offerContinue = await _canOfferContinue(now);
    if (offerContinue) {
      _holdingForContinue = true;
      reviewClock.pause(now);
      _cardTimer.pause(now);
    }
    await _recordFinishedSession(now, dayBoundary);
    if (!offerContinue) completeHeldSession();
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

  Future<void> _countStudyDay(DateTime now, StartOfDay dayBoundary) async {
    if (_countedStudyDay) return;
    final streak = await progressRepository.getStreak();
    await progressRepository.saveStreak(
      streakService.recordCompletion(streak, now, startOfDay: dayBoundary),
    );
    _countedStudyDay = true;
  }

  Future<void> _recordFinishedSession(
    DateTime now,
    StartOfDay dayBoundary,
  ) async {
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
      allowsNewKanji: await _allowsNewKanji(),
    )) {
      return;
    }
    if (plan.completed) return;
    await progressRepository.saveDailySessionPlan(
      plan.copyWith(completed: true),
    );
    _goalCompleted = true;
  }

  Future<bool> _allowsNewKanji() async {
    final access = curriculumAccess;
    if (access == null) return true;
    await access.ensureLoaded();
    return access.canLearnNewKanji;
  }

  bool _introductionBlocked(KanjiCard card) {
    final access = curriculumAccess;
    if (access == null || !access.isLoaded || isPractice) return false;
    if (!_needsLearn(card)) return false;
    return !access.canIntroduce(card.id);
  }

  void _dropBlockedNewCards() {
    while (session.current != null && _introductionBlocked(session.current!)) {
      session.discardCurrent();
    }
  }

  Future<SessionSummary?> _skipBlockedNewCard(
    DateTime now,
    StartOfDay dayBoundary,
  ) async {
    session.discardCurrent();
    _dropBlockedNewCards();
    _offerDueCards(now);
    _visibleCard = session.current;

    if (session.isComplete && await _continueForTimeGoal(now)) {
      _visibleCard = session.current ?? _visibleCard;
    }

    if (session.isComplete) {
      return _closeSession(now, dayBoundary);
    }

    _resetForNextCard();
    return null;
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
    if (session.isDropped(card.id)) return false;
    if (session.hasReviewed(card.id)) return false;
    if (session.queued.any((queued) => queued.id == card.id)) return false;
    if (session.pool.any((pooled) => pooled.id == card.id)) return false;
    if (_introductionBlocked(card)) return false;
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
    final unlearned = session.pool
        .where((card) => _needsLearn(card) && !_introductionBlocked(card))
        .toList();
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
  ///
  /// The returned duration is the estimate from before this sample was folded
  /// in, so the sitting can compare it with the time just spent.
  Future<Duration?> _recordPace({
    required CardSchedule? schedule,
    required bool isNew,
    required Duration duration,
  }) async {
    final active = _cardTimingOpen ? duration : Duration.zero;
    _cardTimingOpen = false;
    if (!CardTimeEstimator.isUsableDuration(active)) return null;
    final current = await progressRepository.getReviewDurationModel();
    final estimator = timeEstimator.withModel(current);
    final predicted = estimator.estimate(schedule, isNew: isNew);
    final next = estimator.learn(
      current,
      schedule: schedule,
      isNew: isNew,
      duration: active,
    );
    if (next == null) return null;
    await progressRepository.saveReviewDurationModel(next);
    return predicted;
  }

  /// Shortens the remaining assigned queue when this sitting is running past
  /// its goal. Practice and Study Anyway sittings are left as opened.
  Future<void> _adaptAssignedQueue(DateTime now) async {
    if (isPractice || isStudyAnyway || _disposed) return;
    try {
      final settings = await progressRepository.getSettings();
      final goal = Duration(minutes: settings.dailyStudyMinutes);
      final estimator = timeEstimator.withModel(
        await progressRepository.getReviewDurationModel(),
      );
      final queue = _queueSnapshots(estimator, now);
      final elapsed = reviewClock.sittingAt(now);
      if (!queueAdjuster.needsAdjustment(
        elapsed: elapsed,
        goal: goal,
        queue: queue,
        adjustmentsUsed: session.adjustmentsMade,
      )) {
        return;
      }
      final replacements = await _replacementSnapshots(estimator, now);
      if (_disposed) return;
      final decision = queueAdjuster.decide(
        elapsed: elapsed,
        goal: goal,
        queue: queue,
        replacements: replacements,
        droppedIds: session.droppedIds,
        adjustmentsUsed: session.adjustmentsMade,
        maxQueueLength: session.initialCount,
      );
      if (!decision.changed) return;
      session.applyAdaptiveSteps(decision.steps);
      lastQueueAdjustment = decision;
      _logAdaptiveQueue(decision);
    } catch (error) {
      if (kDebugMode) debugPrint('Adaptive queue skipped: $error');
    }
  }

  List<AdaptiveQueueCard> _queueSnapshots(
    CardTimeEstimator estimator,
    DateTime now,
  ) {
    final queued = session.queued;
    return [
      for (var i = 0; i < queued.length; i++)
        _queueSnapshot(queued[i], estimator, now, isCurrent: i == 0),
    ];
  }

  AdaptiveQueueCard _queueSnapshot(
    KanjiCard card,
    CardTimeEstimator estimator,
    DateTime now, {
    required bool isCurrent,
  }) {
    final schedule = _schedules[card.id];
    final isNew = selector.isNew(schedule);
    final learning = schedule?.state == CardLearningState.learning;
    final failed = session.isRelearningProtected(card.id);
    return AdaptiveQueueCard(
      id: card.id,
      card: card,
      priority: priorityScorer.score(
        schedule: schedule,
        now: now,
        isNew: isNew,
        level: card.jlptLevel,
      ),
      estimated: _reservedEstimate(estimator, schedule, isNew: isNew),
      protected: isCurrent || failed || isNew || learning,
      isCurrent: isCurrent,
    );
  }

  Future<List<AdaptiveQueueCard>> _replacementSnapshots(
    CardTimeEstimator estimator,
    DateTime now,
  ) async {
    final List<KanjiCard> source;
    if (extraDueReviews != null) {
      source = extraDueReviews!;
    } else if (workloadService != null) {
      source = await workloadService!.eligibleByPriority(now: now);
      final latest = await progressRepository.getSchedules();
      _schedules.addAll(latest);
    } else {
      return const [];
    }
    final snapshots = <AdaptiveQueueCard>[];
    final seen = <String>{};
    for (final card in source) {
      if (!seen.add(card.id)) continue;
      if (!_canReplaceWith(card, now)) continue;
      final schedule = _schedules[card.id];
      snapshots.add(
        AdaptiveQueueCard(
          id: card.id,
          card: card,
          priority: priorityScorer.score(
            schedule: schedule,
            now: now,
            isNew: false,
            level: card.jlptLevel,
          ),
          estimated: _reservedEstimate(estimator, schedule, isNew: false),
          protected: false,
        ),
      );
    }
    return snapshots;
  }

  bool _canReplaceWith(KanjiCard card, DateTime now) {
    if (session.isDropped(card.id) || session.isRelearningProtected(card.id)) {
      return false;
    }
    if (session.hasReviewed(card.id)) return false;
    if (session.queued.any((queued) => queued.id == card.id)) return false;
    if (session.pool.any((pooled) => pooled.id == card.id)) return false;
    final schedule = _schedules[card.id];
    if (selector.isNew(schedule)) return false;
    if (schedule?.state == CardLearningState.learning) return false;
    return selector.isDue(schedule, now, startOfDay: _startOfDay);
  }

  /// One showing from the historical estimator, doubled for a kanji that
  /// still has to be introduced and then retrieved. [SessionPaceTracker]
  /// raises that when this sitting is slower than those estimates.
  Duration _reservedEstimate(
    CardTimeEstimator estimator,
    CardSchedule? schedule, {
    required bool isNew,
  }) {
    final showing = estimator.estimate(schedule, isNew: isNew);
    final seconds = showing.inSeconds < 1 ? 1 : showing.inSeconds;
    return _pace.scale(Duration(seconds: isNew ? seconds * 2 : seconds));
  }

  void _logAdaptiveQueue(AdaptiveQueueDecision decision) {
    if (!kDebugMode) return;
    for (final step in decision.steps) {
      developer.log(
        'elapsed=${decision.elapsed.inSeconds}s '
        'estimatedRemainingBefore=${decision.estimatedRemainingBefore.inSeconds}s '
        'projected=${decision.projectedBefore.inSeconds}s '
        'goal=${decision.goal.inSeconds}s '
        'protected=${decision.protectedCount} '
        'eligible=${decision.eligibleIds.join(',')} '
        'removed=${step.removedId} '
        'swappedIn=${step.replacementId ?? '-'} '
        'saved=${step.estimatedSaved.inSeconds}s '
        'projectedAfter=${decision.projectedAfter.inSeconds}s',
        name: 'adaptive_queue',
      );
    }
  }

  void _resetForNextCard() {
    _dropBlockedNewCards();
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

  void _scheduleSessionStart() {
    if (_sessionStartScheduled || isPractice || !ready) return;
    if (session.current == null) return;
    _sessionStartScheduled = true;
    _startFuture = _emitSessionStart();
  }

  Future<void> _emitSessionStart() async {
    if (_sessionStarted) return;
    _sessionType = await _resolveSessionType();
    if (_sessionStarted) return;
    _sessionStarted = true;
    analytics.studySessionStarted(
      sessionType: _sessionType,
      availableCards: session.initialCount,
    );
  }

  Future<String> _resolveSessionType() async {
    if (isStudyAnyway) return 'study_anyway';
    try {
      final plan = await progressRepository.getDailySessionPlan();
      if (plan.dayType == StudyDayType.reinforcement) return 'reinforcement';
    } catch (_) {}
    return 'normal';
  }

  /// Ends analytics for a sitting that reached its real completion state.
  ///
  /// The continue prompt is not completion. Leaving that prompt, or finishing
  /// with nothing left to study, is.
  void completeHeldSession() {
    if (isPractice || _analyticsFinished) return;
    _analyticsFinished = true;
    unawaited(_emitCompleted());
  }

  /// Leaves an open sitting. Backgrounding does not call this.
  ///
  /// A sitting already paused on the continue prompt is completed: the
  /// planned queue is done and its answers can no longer be undone.
  void abandonIfUnfinished() {
    if (isPractice || _analyticsFinished) return;
    if (_holdingForContinue) {
      completeHeldSession();
      return;
    }
    _analyticsFinished = true;
    unawaited(_emitAbandoned());
  }

  Future<void> _emitCompleted() async {
    await _startFuture;
    if (!_sessionStarted) return;
    _flushPendingReviews();
    analytics.studySessionCompleted(
      durationSeconds: _sessionDurationSeconds(),
      cardsReviewed: session.reviewedCount,
      newCardsLearned: _newCardsLearned,
      goalCompleted: _goalCompleted,
      sessionType: _sessionType,
    );
  }

  Future<void> _emitAbandoned() async {
    await _startFuture;
    if (!_sessionStarted) return;
    _flushPendingReviews();
    analytics.studySessionAbandoned(
      durationSeconds: _sessionDurationSeconds(),
      cardsReviewed: session.reviewedCount,
      sessionType: _sessionType,
    );
  }

  int _sessionDurationSeconds() {
    final seconds = reviewClock.sittingAt(clock()).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  /// Sends reviews whose undo window has closed. An undone answer is removed
  /// from [_pendingReviews] and is not sent.
  void _flushPendingReviews() {
    if (isPractice) {
      _pendingReviews.clear();
      return;
    }
    for (final review in _pendingReviews) {
      analytics.kanjiReviewed(
        result: review.result,
        isNew: review.isNew,
        reviewCategory: review.reviewCategory,
      );
    }
    _pendingReviews.clear();
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
    required this.paceTracker,
    required this.historyEntry,
    required this.drawing,
    required this.answer,
    required this.suggestedResult,
    required this.phase,
    required this.trackedReview,
  });

  final ReviewSessionCheckpoint session;
  final String cardId;
  final CardSchedule? schedule;
  final bool hadSchedule;
  final ReviewDurationModel pace;
  final SessionPaceSnapshot paceTracker;
  final ReviewHistoryEntry historyEntry;
  final HandwritingInput drawing;
  final ReviewAnswer? answer;
  final ReviewResult? suggestedResult;
  final StudyPhase phase;
  final bool trackedReview;
}
