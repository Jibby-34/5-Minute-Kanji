import '../core/models/curriculum.dart';
import '../core/models/kanji_card.dart';

abstract class KanjiRepository {
  Future<List<KanjiCard>> getAll();

  Future<KanjiCard?> getById(String id);

  Future<Curriculum?> getCurriculum(String id);
}
