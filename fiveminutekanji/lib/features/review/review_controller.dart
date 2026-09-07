import 'package:flutter/foundation.dart';

import '../../core/models/card_schedule.dart';
import '../../core/models/handwriting.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/progress.dart';
import '../../core/models/review.dart';
import '../../core/models/study_phase.dart';
import '../../core/utils/clock.dart';
import '../../repositories/progress_repository.dart';
import '../../services/answer_grader.dart';
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
    this.streakService = const StreakService(),
    this.grader = const ManualAnswerGrader(),
    this.statusResolver = const KanjiStatusResolver(),
    this.selector = const DueCardSelector(),
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
         startTime: startTime,
       ) {
    _cardShownAt = this.clock();
    if (schedules != null) {
      _schedules = Map<String, CardSchedule>.from(schedules);
      _applyPhaseForCurrent();
      ready = true;
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
  final bool isPractice;
  final ReviewSession session;

  bool ready = false;
  bool busy = false;
  StudyPhase phase = StudyPhase.recall;
  HandwritingInput drawing = HandwritingInput.empty;
  ReviewAnswer? answer;
  ReviewResult? suggestedResult;
  late DateTime _cardShownAt;
  SessionSummary? summary;
  KanjiCard? _visibleCard;
  Map<String, CardSchedule> _schedules = {};
  int padGeneration = 0;
  bool _disposed = false;

  KanjiCard? get current => session.current ?? _visibleCard;

  bool get isComplete => session.isComplete;

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
    if (ready || _disposed) return;
    final schedules = await progressRepository.getSchedules();
    if (_disposed || ready) return;
    _schedules = Map<String, CardSchedule>.from(schedules);
    _applyPhaseForCurrent();
    ready = true;
    notifyListeners();
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
    try {
      final existing =
          await progressRepository.getSchedule(card.id) ??
          CardSchedule.fresh(card.id, now);
      final updated = srsEngine.introduce(current: existing, now: now);
      await progressRepository.saveSchedule(updated);
      _schedules[card.id] = updated;
      if (existing.state == CardLearningState.newCard) {
        final daily = (await progressRepository.getDailyNewKanji()).forDay(now);
        await progressRepository.saveDailyNewKanji(daily.increment());
      }

      session.completeIntroduction();
      _offerDueCards(now);
      _visibleCard = session.current ?? card;

      if (session.isComplete) {
        final streak = await progressRepository.getStreak();
        await progressRepository.saveStreak(
          streakService.recordCompletion(streak, now),
        );
        summary = session.toSummary(
          now: now,
          nextReviewAt: await _soonestDue(now),
        );
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
      final updated = await markAsKnown.markKanjiAsKnown(card.id, now: now);
      if (updated != null) {
        _schedules[card.id] = updated;
      }

      session.completeIntroduction();
      _offerDueCards(now);
      _visibleCard = session.current ?? card;

      if (session.isComplete) {
        final streak = await progressRepository.getStreak();
        await progressRepository.saveStreak(
          streakService.recordCompletion(streak, now),
        );
        summary = session.toSummary(
          now: now,
          nextReviewAt: await _soonestDue(now),
        );
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
    final timeOnCard = now.difference(_cardShownAt);

    try {
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
      }

      await progressRepository.addHistory(
        ReviewHistoryEntry(
          cardId: card.id,
          rating: result,
          timestamp: now,
          timeOnCard: timeOnCard.isNegative ? Duration.zero : timeOnCard,
          isPractice: isPractice,
        ),
      );

      session.recordRating(result);
      if (!isPractice) {
        _offerDueCards(now);
      }
      _visibleCard = session.current ?? card;

      if (session.isComplete) {
        final streak = await progressRepository.getStreak();
        await progressRepository.saveStreak(
          streakService.recordCompletion(streak, now),
        );
        summary = session.toSummary(
          now: now,
          nextReviewAt: await _soonestDue(now),
        );
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

  bool _needsLearn(KanjiCard card) {
    if (session.hasReviewed(card.id)) return false;
    final schedule = _schedules[card.id];
    return schedule == null || schedule.state == CardLearningState.newCard;
  }

  void _offerDueCards(DateTime now) {
    final due = selector.select(
      cards: session.pool,
      schedules: _schedules,
      now: now,
      limit: session.pool.length,
      maxNewCards: 0,
    );
    session.offerDue(due);
  }

  void _applyPhaseForCurrent() {
    final card = current;
    if (card == null) return;
    phase = _needsLearn(card) ? StudyPhase.learn : StudyPhase.recall;
  }

  void _resetForNextCard() {
    drawing = HandwritingInput.empty;
    answer = null;
    suggestedResult = null;
    padGeneration++;
    _cardShownAt = clock();
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
