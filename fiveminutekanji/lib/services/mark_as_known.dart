import '../core/models/card_schedule.dart';
import '../core/utils/clock.dart';
import '../repositories/progress_repository.dart';
import 'initial_known_card_schedule.dart';
import 'srs_scheduler.dart';

/// Shared entry point for individual and mass "Mark as Known".
///
/// Does not increment the daily new-kanji allowance. Does not overwrite
/// cards that already have SRS progress. Both individual and bulk paths
/// use [calculateInitialKnownCardSchedule] for the first interval, then
/// persist that due date through [SrsScheduler.markAsKnown]. Later
/// reviews use [SrsScheduler.schedule], not this helper.
class MarkAsKnownService {
  const MarkAsKnownService({
    required this.progressRepository,
    required this.srsEngine,
    Clock? clock,
  }) : clock = clock ?? DateTime.now;

  final ProgressRepository progressRepository;
  final SrsScheduler srsEngine;
  final Clock clock;

  Future<CardSchedule?> markKanjiAsKnown(String cardId, {DateTime? now}) async {
    final marked = await markKanjiAsKnownAll([cardId], now: now);
    return marked.isEmpty ? null : marked.first;
  }

  Future<List<CardSchedule>> markKanjiAsKnownAll(
    Iterable<String> cardIds, {
    DateTime? now,
  }) async {
    final timestamp = now ?? clock();
    final ids = cardIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return const [];

    final existing = await progressRepository.getSchedules();
    final updated = <CardSchedule>[];
    for (final id in ids) {
      final current = existing[id] ?? CardSchedule.fresh(id, timestamp);
      if (current.state != CardLearningState.newCard) continue;
      updated.add(
        srsEngine.markAsKnown(
          current: current,
          now: timestamp,
          interval: calculateInitialKnownCardSchedule(id),
        ),
      );
    }
    if (updated.isEmpty) return const [];
    await progressRepository.saveSchedules(updated);
    return updated;
  }
}
