import '../core/models/curriculum.dart';
import '../core/models/kanji_card.dart';
import '../repositories/kanji_repository.dart';
import 'hardcoded_kanji_data.dart';
import 'kanji_dataset_check.dart';

class HardcodedKanjiRepository implements KanjiRepository {
  const HardcodedKanjiRepository();

  static final Map<String, KanjiCard> _byId = _cardsById(hardcodedKanjiCards);

  static Map<String, KanjiCard> _cardsById(List<KanjiCard> cards) {
    assert(() {
      final problems = kanjiDatasetProblems(cards);
      if (problems.isNotEmpty) {
        throw StateError(
          'Kanji dataset is invalid:\n${problems.take(12).join('\n')}',
        );
      }
      return true;
    }());
    return {for (final card in cards) card.id: card};
  }

  @override
  Future<List<KanjiCard>> getAll() async =>
      List.unmodifiable(hardcodedKanjiCards);

  @override
  Future<KanjiCard?> getById(String id) async => _byId[id];

  @override
  Future<Curriculum?> getCurriculum(String id) async {
    if (id == rtkMvpCurriculumId) return rtkMvpCurriculum;
    return null;
  }
}
