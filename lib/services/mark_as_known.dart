import '../core/models/card_schedule.dart';
import '../core/utils/clock.dart';
import '../repositories/kanji_repository.dart';
import '../repositories/progress_repository.dart';
import 'initial_known_card_schedule.dart';
import 'srs_scheduler.dart';

/// Shared entry point for individual and mass "Mark as Known".
///
/// Does not increment the daily new-kanji allowance. Does not overwrite
/// cards that already have SRS progress. Both individual and bulk paths,
/// including the placement test, use
/// [calculateProficiencyAdjustedKnownInterval] for the first interval when
/// the kanji has a difficulty score. Later reviews use [SrsScheduler.schedule],
/// not this helper.
class MarkAsKnownService {
  const MarkAsKnownService({
    required this.progressRepository,
    required this.srsEngine,
    this.kanjiRepository,
    Clock? clock,
  }) : clock = clock ?? DateTime.now;

  final ProgressRepository progressRepository;
  final SrsScheduler srsEngine;

  /// Catalog used for difficulty scores. Without it, the first interval
  /// falls back to the legacy day scatter.
  final KanjiRepository? kanjiRepository;
  final Clock clock;

  Future<CardSchedule?> markKanjiAsKnown(String cardId, {DateTime? now}) async {
    final marked = await markKanjiAsKnownAll([cardId], now: now);
    return marked.isEmpty ? null : marked.first;
  }

  /// [proficiencyEstimate] is the placement posterior for this batch. Manual
  /// marks leave it null and read the saved placement instead.
  Future<List<CardSchedule>> markKanjiAsKnownAll(
    Iterable<String> cardIds, {
    DateTime? now,
    double? proficiencyEstimate,
  }) async {
    final timestamp = now ?? clock();
    final ids = cardIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return const [];

    final existing = await progressRepository.getSchedules();
    final toMark = <String>[];
    for (final id in ids) {
      final current = existing[id] ?? CardSchedule.fresh(id, timestamp);
      if (current.state != CardLearningState.newCard) continue;
      toMark.add(id);
    }
    if (toMark.isEmpty) return const [];

    final difficulties = await _difficultiesById();
    final knownDifficulties = difficulties == null
        ? const <int>[]
        : _knownDifficulties(
            existing: existing,
            difficulties: difficulties,
            marking: toMark.toSet(),
          );
    final proficiency = difficulties == null
        ? null
        : await _proficiency(proficiencyEstimate);

    final updated = <CardSchedule>[];
    for (final id in toMark) {
      final current = existing[id] ?? CardSchedule.fresh(id, timestamp);
      updated.add(
        srsEngine.markAsKnown(
          current: current,
          now: timestamp,
          interval: _intervalFor(
            id: id,
            difficulty: difficulties?[id],
            knownDifficulties: knownDifficulties,
            proficiency: proficiency,
          ),
        ),
      );
    }
    await progressRepository.saveSchedules(updated);
    return updated;
  }

  Future<Map<String, int>?> _difficultiesById() async {
    final repository = kanjiRepository;
    if (repository == null) return null;
    final cards = await repository.getAll();
    return {for (final card in cards) card.id: card.difficulty};
  }

  Future<KnownIntervalProficiency> _proficiency(double? estimate) async {
    final placement = await progressRepository.getPlacement();
    return proficiencyFromPlacement(
      estimatedDifficulty: estimate ?? placement.estimatedDifficulty,
      selfAssessment: placement.selfAssessment,
    );
  }

  List<int> _knownDifficulties({
    required Map<String, CardSchedule> existing,
    required Map<String, int> difficulties,
    required Set<String> marking,
  }) {
    final scores = <int>[];
    for (final schedule in existing.values) {
      if (marking.contains(schedule.cardId)) continue;
      if (!scheduleCountsAsKnownKanji(schedule)) continue;
      final score = difficulties[schedule.cardId];
      if (score != null) scores.add(score);
    }
    for (final id in marking) {
      final score = difficulties[id];
      if (score != null) scores.add(score);
    }
    return scores;
  }

  Duration _intervalFor({
    required String id,
    required int? difficulty,
    required List<int> knownDifficulties,
    required KnownIntervalProficiency? proficiency,
  }) {
    if (difficulty == null ||
        proficiency == null ||
        !knownDifficultyIsValid(difficulty)) {
      return calculateInitialKnownCardSchedule(id);
    }
    return calculateProficiencyAdjustedKnownInterval(
      kanjiId: id,
      difficulty: difficulty,
      knownDifficulties: knownDifficulties,
      proficiency: proficiency,
    );
  }
}
