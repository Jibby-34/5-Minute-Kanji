import 'dart:math' as math;

import '../core/models/card_schedule.dart';
import '../core/models/kanji_card.dart';
import '../core/models/placement.dart';
import '../core/utils/clock.dart';
import '../repositories/kanji_repository.dart';
import '../repositories/progress_repository.dart';
import 'due_card_selector.dart';
import 'mark_as_known.dart';
import 'placement_model.dart';

/// Owns everything the placement test does outside of the question algorithm:
/// which kanji it may ask about, saving an unfinished run, and turning a result
/// into real progress.
///
/// Results go through [MarkAsKnownService], so a kanji the test marks is
/// indistinguishable from one marked by hand in the kanji list.
class PlacementService {
  PlacementService({
    required this.kanjiRepository,
    required this.progressRepository,
    required this.markAsKnown,
    this.selector = const DueCardSelector(),
    Clock? clock,
  }) : clock = clock ?? DateTime.now;

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final MarkAsKnownService markAsKnown;
  final DueCardSelector selector;
  final Clock clock;

  Future<PlacementProgress> progress() => progressRepository.getPlacement();

  /// Whether the first-launch test still has to run.
  ///
  /// An empty kanji set is a reason to wait, not to skip: the flag would be
  /// spent on a user who was never asked anything.
  Future<bool> isRequired() async {
    final placement = await progressRepository.getPlacement();
    if (placement.completed) return false;

    final cards = await kanjiRepository.getAll();
    if (cards.isEmpty) return false;

    final pool = await candidates();
    if (pool.isEmpty) {
      // Everything is already learned or manually marked known; there is
      // nothing left to place and no reason to ask again.
      await _save(placement.copyWith(completed: true, answers: const []));
      return false;
    }
    return true;
  }

  /// The full catalog. Used to describe where an estimate sits, including
  /// kanji the test is not allowed to ask about.
  Future<List<KanjiCard>> catalog() => kanjiRepository.getAll();

  /// A stable mix for question choice, created once per run.
  Future<int> ensureSelectionSeed() async {
    final placement = await progressRepository.getPlacement();
    if (placement.selectionSeed != 0) return placement.selectionSeed;
    final raw = clock().microsecondsSinceEpoch & 0x7fffffff;
    final seed = raw == 0 ? 1 : raw;
    await _save(placement.copyWith(selectionSeed: seed));
    return seed;
  }

  /// Kanji the test may ask about: the ones the app has no progress for.
  /// Already-known kanji are left out — their answer is on record.
  Future<List<KanjiCard>> candidates() async {
    final cards = await kanjiRepository.getAll();
    final schedules = await progressRepository.getSchedules();
    return [
      for (final card in cards)
        if (selector.isNew(schedules[card.id])) card,
    ]..sort(compareKanjiLearnOrder);
  }

  /// Persists an unfinished run so closing the app does not lose it.
  Future<void> saveAnswers(List<PlacementAnswer> answers) async {
    final placement = await progressRepository.getPlacement();
    await _save(placement.copyWith(answers: answers));
  }

  /// Stores the learner's starting guess. Does not mark any kanji known.
  Future<void> saveSelfAssessment(PlacementSelfAssessment assessment) async {
    final placement = await progressRepository.getPlacement();
    await _save(placement.copyWith(selfAssessment: assessment));
  }

  /// Marks the kanji the test found, then records the test as done.
  ///
  /// Cards that already have SRS progress are left alone. A retake can add
  /// placements for kanji that are still new; it does not reset the library.
  Future<PlacementSummary> complete(PlacementOutcome outcome) async {
    final now = clock();
    final marked = await markAsKnown.markKanjiAsKnownAll(
      outcome.knownCardIds,
      now: now,
    );
    final confirmed = await _confirmNewCards(outcome.confirmCardIds, now);
    final placement = await progressRepository.getPlacement();
    await _save(
      PlacementProgress(
        completed: true,
        selfAssessment: placement.selfAssessment,
      ),
    );
    return PlacementSummary(
      knownCount: marked.length,
      confirmCount: confirmed,
      headline: outcome.headline,
      detail: outcome.detail,
      nothingToPlace: outcome.nothingToPlace,
    );
  }

  /// Clears an unfinished run for a retake. Keeps [PlacementProgress.completed]
  /// so abandoning a retake cannot bring the test back on the next launch.
  Future<void> restart() async {
    final placement = await progressRepository.getPlacement();
    await _save(
      placement.copyWith(
        answers: const [],
        selectionSeed: 0,
        clearSelfAssessment: true,
      ),
    );
  }

  /// Puts likely-but-untested kanji into learning, spread over later days so
  /// they confirm gradually instead of filling today's session.
  Future<int> _confirmNewCards(List<String> ids, DateTime now) async {
    if (ids.isEmpty) return 0;
    final existing = await progressRepository.getSchedules();
    final horizon = math.max(placementConfirmMinHorizonDays, ids.length);
    final updated = <CardSchedule>[];
    for (final id in ids) {
      if (id.isEmpty) continue;
      final current = existing[id] ?? CardSchedule.fresh(id, now);
      if (current.state != CardLearningState.newCard) continue;
      final days = 1 + _dayBucket(id, horizon);
      final interval = Duration(days: days);
      updated.add(
        current.copyWith(
          state: CardLearningState.learning,
          interval: interval,
          dueAt: now.add(interval),
        ),
      );
    }
    if (updated.isEmpty) return 0;
    await progressRepository.saveSchedules(updated);
    return updated.length;
  }

  int _dayBucket(String id, int span) {
    var hash = 2166136261;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash % span;
  }

  Future<void> _save(PlacementProgress placement) =>
      progressRepository.savePlacement(placement);
}
