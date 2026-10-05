import '../core/models/kanji_card.dart';
import '../core/models/placement.dart';
import '../core/utils/clock.dart';
import '../repositories/kanji_repository.dart';
import '../repositories/progress_repository.dart';
import 'due_card_selector.dart';
import 'mark_as_known.dart';

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

  /// Marks the kanji the test found, then records the test as done.
  Future<PlacementSummary> complete(PlacementOutcome outcome) async {
    final marked = await markAsKnown.markKanjiAsKnownAll(
      outcome.knownCardIds,
      now: clock(),
    );
    await _save(const PlacementProgress(completed: true));
    return PlacementSummary(
      knownCount: marked.length,
      startingLevel: outcome.startingLevel,
      resumesMidLevel: outcome.resumesMidLevel,
    );
  }

  /// Clears an unfinished run for a retake. Keeps [PlacementProgress.completed]
  /// so abandoning a retake cannot bring the test back on the next launch.
  Future<void> restart() async {
    final placement = await progressRepository.getPlacement();
    await _save(placement.copyWith(answers: const []));
  }

  Future<void> _save(PlacementProgress placement) =>
      progressRepository.savePlacement(placement);
}
