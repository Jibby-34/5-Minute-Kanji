import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/models/card_schedule.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/progress.dart';
import '../../core/models/review.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/time_format.dart';
import '../../repositories/kanji_repository.dart';
import '../../repositories/progress_repository.dart';
import '../../services/due_card_selector.dart';
import '../../services/session_new_card_budget.dart';

class HomeController extends ChangeNotifier {
  HomeController({
    required this.kanjiRepository,
    required this.progressRepository,
    this.config = ReviewSessionConfig.fiveMinute,
    this.selector = const DueCardSelector(),
    Clock? clock,
  }) : clock = clock ?? DateTime.now;

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final ReviewSessionConfig config;
  final DueCardSelector selector;
  final Clock clock;

  bool loading = true;
  int dueCount = 0;
  int newRemainingToday = 0;
  int estimatedMinutes = 0;
  int streak = 0;
  DateTime? nextReviewAt;

  /// New kanji still left in today's allowance. Decreases when a card is
  /// learned, not when it is retrieved for the first time.
  int get remainingToday => newRemainingToday;

  bool get isCaughtUp => !loading && dueCount == 0 && newRemainingToday == 0;

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) {
      loading = true;
      notifyListeners();
    }

    try {
      final cards = await kanjiRepository.getAll();
      final schedules = await progressRepository.getSchedules();
      final settings = await progressRepository.getSettings();
      final streakInfo = await progressRepository.getStreak();
      final now = clock();
      final sessionConfig = config.copyWith(
        averageSecondsPerCard: settings.averageSecondsPerCard,
      );
      final daily = (await progressRepository.getDailyNewKanji()).forDay(now);
      final remainingDaily = daily.remainingAllowance(settings.newKanjiPerDay);
      final unencountered = selector.countNew(
        cards: cards,
        schedules: schedules,
      );

      final due = selector.countDue(
        cards: cards,
        schedules: schedules,
        now: now,
      );
      final remainingNew = math.min(unencountered, remainingDaily);
      final selected = selector.select(
        cards: cards,
        schedules: schedules,
        now: now,
        limit: sessionConfig.effectiveMaxCards,
        maxNewCards: sessionNewCardLimit(
          sessionCapacity: sessionConfig.effectiveMaxCards,
          dueReviewCount: due,
          remainingDaily: remainingNew,
        ),
      );

      dueCount = due;
      newRemainingToday = remainingNew;
      estimatedMinutes = estimateReviewMinutes(
        dueCount: selected.length,
        averageSecondsPerCard: settings.averageSecondsPerCard,
      );
      streak = streakInfo.current;
      nextReviewAt = _nextReviewAt(
        cards: cards,
        schedules: schedules,
        now: now,
        settings: settings,
        unencountered: unencountered,
        remainingNew: remainingNew,
      );
    } catch (_) {
      dueCount = 0;
      newRemainingToday = 0;
      estimatedMinutes = 0;
      streak = 0;
      nextReviewAt = null;
    }

    loading = false;
    notifyListeners();
  }

  Future<List<KanjiCard>> cardsForSession({required bool practice}) async {
    final cards = await kanjiRepository.getAll();
    if (cards.isEmpty) return const [];

    final settings = await progressRepository.getSettings();
    final sessionConfig = config.copyWith(
      averageSecondsPerCard: settings.averageSecondsPerCard,
    );
    final limit = sessionConfig.effectiveMaxCards;

    if (practice) {
      final shuffled = List<KanjiCard>.from(cards)..shuffle();
      return shuffled.take(limit).toList();
    }

    final now = clock();
    final schedules = await progressRepository.getSchedules();
    final daily = (await progressRepository.getDailyNewKanji()).forDay(now);
    final remainingDaily = daily.remainingAllowance(settings.newKanjiPerDay);
    final due = selector.countDue(cards: cards, schedules: schedules, now: now);
    final remainingNew = math.min(
      selector.countNew(cards: cards, schedules: schedules),
      remainingDaily,
    );

    return selector.select(
      cards: cards,
      schedules: schedules,
      now: now,
      limit: limit,
      maxNewCards: sessionNewCardLimit(
        sessionCapacity: limit,
        dueReviewCount: due,
        remainingDaily: remainingNew,
      ),
    );
  }

  DateTime? _nextReviewAt({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
    required AppSettings settings,
    required int unencountered,
    required int remainingNew,
  }) {
    if (dueCount > 0 || remainingNew > 0) return now;

    final nextDue = selector.nextFutureDue(
      cards: cards,
      schedules: schedules,
      now: now,
    );

    if (unencountered > 0 && settings.newKanjiPerDay > 0) {
      final tomorrow = calendarDay(now).add(const Duration(days: 1));
      if (nextDue == null || tomorrow.isBefore(nextDue)) return tomorrow;
    }
    return nextDue;
  }
}
