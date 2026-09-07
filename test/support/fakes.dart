import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/curriculum.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/repositories/kanji_repository.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';

KanjiCard testCard(
  String id, {
  String? keyword,
  String? character,
  JlptLevel jlptLevel = JlptLevel.none,
}) {
  return KanjiCard(
    id: id,
    character: character ?? id,
    meaning: keyword ?? id,
    keyword: keyword ?? id,
    mnemonic: 'mnemonic $id',
    components: const [],
    strokeCount: 1,
    jlptLevel: jlptLevel,
  );
}

class FakeKanjiRepository implements KanjiRepository {
  FakeKanjiRepository(this.cards);

  final List<KanjiCard> cards;

  @override
  Future<List<KanjiCard>> getAll() async => List.unmodifiable(cards);

  @override
  Future<KanjiCard?> getById(String id) async {
    for (final card in cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  @override
  Future<Curriculum?> getCurriculum(String id) async => null;
}

class MemoryProgressRepository implements ProgressRepository {
  MemoryProgressRepository({
    Map<String, CardSchedule>? schedules,
    this.settings = const AppSettings(),
    this.dailyNewKanji = DailyNewKanjiProgress.empty,
  }) : schedules = schedules ?? {};

  final Map<String, CardSchedule> schedules;
  final List<ReviewHistoryEntry> history = [];
  StreakInfo streak = StreakInfo.empty;
  AppSettings settings;
  DailyNewKanjiProgress dailyNewKanji;

  @override
  Future<Map<String, CardSchedule>> getSchedules() async =>
      Map.unmodifiable(schedules);

  @override
  Future<CardSchedule?> getSchedule(String cardId) async => schedules[cardId];

  @override
  Future<void> saveSchedule(CardSchedule schedule) async {
    await saveSchedules([schedule]);
  }

  @override
  Future<void> saveSchedules(Iterable<CardSchedule> next) async {
    for (final schedule in next) {
      schedules[schedule.cardId] = schedule;
    }
  }

  @override
  Future<List<ReviewHistoryEntry>> getHistory() async =>
      List.unmodifiable(history);

  @override
  Future<void> addHistory(ReviewHistoryEntry entry) async {
    history.add(entry);
  }

  @override
  Future<StreakInfo> getStreak() async => streak;

  @override
  Future<void> saveStreak(StreakInfo next) async {
    streak = next;
  }

  @override
  Future<AppSettings> getSettings() async => settings;

  @override
  Future<void> saveSettings(AppSettings next) async {
    settings = next;
  }

  @override
  Future<DailyNewKanjiProgress> getDailyNewKanji() async => dailyNewKanji;

  @override
  Future<void> saveDailyNewKanji(DailyNewKanjiProgress next) async {
    dailyNewKanji = next;
  }

  @override
  Future<void> seedIfNeeded(List<String> cardIds, {DateTime? now}) async {
    final timestamp = now ?? DateTime.now();
    for (final id in cardIds) {
      schedules.putIfAbsent(id, () => CardSchedule.fresh(id, timestamp));
    }
  }
}
