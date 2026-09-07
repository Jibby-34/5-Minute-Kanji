import '../core/models/curriculum.dart';
import '../core/models/kanji_card.dart';
import '../repositories/kanji_repository.dart';
import 'hardcoded_kanji_data.dart';

class HardcodedKanjiRepository implements KanjiRepository {
  const HardcodedKanjiRepository();

  static final Map<String, KanjiCard> _byId = {
    for (final card in hardcodedKanjiCards) card.id: card,
  };

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
