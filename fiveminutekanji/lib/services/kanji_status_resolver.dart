import '../core/models/card_schedule.dart';
import '../core/models/kanji_status.dart';

/// Maps persisted SRS state to list/detail status colors.
///
/// New cards are not encountered. Completing the Learn flow moves a card
/// into learning. Change [masteredConsecutiveGoods] to adjust mastered
/// without touching UI or persistence.
class KanjiStatusResolver {
  const KanjiStatusResolver();

  static const int masteredConsecutiveGoods = 3;

  KanjiProgressStatus resolve(CardSchedule? schedule) {
    if (schedule == null || schedule.state == CardLearningState.newCard) {
      return KanjiProgressStatus.notEncountered;
    }
    if (schedule.consecutiveGoodCount >= masteredConsecutiveGoods) {
      return KanjiProgressStatus.mastered;
    }
    return KanjiProgressStatus.learning;
  }
}
