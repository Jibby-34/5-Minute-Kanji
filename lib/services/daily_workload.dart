import 'dart:math' as math;

import '../core/models/card_schedule.dart';
import '../core/models/kanji_card.dart';
import '../core/models/progress.dart';
import '../core/models/review.dart';
import '../core/models/start_of_day.dart';
import '../core/utils/time_format.dart';
import '../repositories/kanji_repository.dart';
import '../repositories/progress_repository.dart';
import 'due_card_selector.dart';
import 'session_new_card_budget.dart';

/// One reading of what is left in the current study day.
///
/// The Home screen and the daily reminder both render this snapshot, so the
/// two can never disagree about the day's workload.
class DailyWorkload {
  const DailyWorkload({
    required this.dueCount,
    required this.newRemainingToday,
    required this.estimatedMinutes,
    required this.startOfDay,
    this.nextReviewAt,
    this.sessionCards = const [],
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

  /// Home's `~n min` estimate for the sitting that is waiting.
  final int estimatedMinutes;

  final StartOfDay startOfDay;
  final DateTime? nextReviewAt;

  /// Cards a sitting started now would draw from.
  final List<KanjiCard> sessionCards;

  bool get isCaughtUp => dueCount == 0 && newRemainingToday == 0;

  /// True when the headline count refers to new kanji rather than reviews.
  /// Mirrors how Home picks its wording.
  bool get countsNewKanji => newRemainingToday > 0;

  /// The single number Home puts on screen: new kanji first, then reviews.
  int get remainingCount => countsNewKanji ? newRemainingToday : dueCount;
}

/// Computes the day's workload from progress + settings.
///
/// This is the only place the "what is left today" arithmetic lives.
class DailyWorkloadService {
  const DailyWorkloadService({
    required this.kanjiRepository,
    required this.progressRepository,
    this.config = ReviewSessionConfig.fiveMinute,
    this.selector = const DueCardSelector(),
  });

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final ReviewSessionConfig config;
  final DueCardSelector selector;

  Future<DailyWorkload> read({required DateTime now}) async {
    final cards = await kanjiRepository.getAll();
    final schedules = await progressRepository.getSchedules();
    final settings = await progressRepository.getSettings();
    final dayBoundary = settings.startOfDay;
    final sessionConfig = config.copyWith(
      averageSecondsPerCard: settings.averageSecondsPerCard,
    );
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
    final budget = sessionCardBudget(
      sessionCapacity: sessionConfig.effectiveMaxCards,
      dueReviewCount: due,
      remainingDaily: remainingNew,
    );
    final selected = selector.select(
      cards: cards,
      schedules: schedules,
      now: now,
      limit: budget.sessionLimit,
      maxNewCards: budget.maxNewCards,
      startOfDay: dayBoundary,
    );

    return DailyWorkload(
      dueCount: due,
      newRemainingToday: remainingNew,
      estimatedMinutes: estimateReviewMinutes(
        dueCount: selected.length,
        averageSecondsPerCard: settings.averageSecondsPerCard,
      ),
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
      sessionCards: selected,
    );
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
