import 'package:flutter/foundation.dart';

import '../../core/models/card_schedule.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/kanji_status.dart';
import '../../repositories/kanji_repository.dart';
import '../../repositories/progress_repository.dart';
import '../../services/kanji_status_resolver.dart';
import '../../services/mark_as_known.dart';
import '../../services/srs_engine.dart';
import '../../services/srs_scheduler.dart';

class KanjiListItem {
  const KanjiListItem({
    required this.card,
    required this.schedule,
    required this.status,
  });

  final KanjiCard card;
  final CardSchedule? schedule;
  final KanjiProgressStatus status;

  bool get isNew => status == KanjiProgressStatus.notEncountered;
}

class KanjiListSection {
  const KanjiListSection({required this.level, required this.items});

  final JlptLevel level;
  final List<KanjiListItem> items;
}

List<KanjiListSection> groupKanjiByJlpt(List<KanjiListItem> items) {
  return [
    for (final level in JlptLevel.sectionOrder)
      KanjiListSection(
        level: level,
        items: [
          for (final item in items)
            if (item.card.jlptLevel == level) item,
        ],
      ),
  ].where((section) => section.items.isNotEmpty).toList();
}

class KanjiListController extends ChangeNotifier {
  KanjiListController({
    required this.kanjiRepository,
    required this.progressRepository,
    this.resolver = const KanjiStatusResolver(),
    SrsScheduler? srsEngine,
    MarkAsKnownService? markAsKnown,
  }) : markAsKnown =
           markAsKnown ??
           MarkAsKnownService(
             progressRepository: progressRepository,
             srsEngine: srsEngine ?? const SrsEngine(),
           );

  final KanjiRepository kanjiRepository;
  final ProgressRepository progressRepository;
  final KanjiStatusResolver resolver;
  final MarkAsKnownService markAsKnown;

  bool loading = true;
  bool selecting = false;
  bool busy = false;
  List<KanjiListItem> items = const [];
  final Set<String> selectedIds = {};

  List<KanjiListSection> get sections => groupKanjiByJlpt(items);

  int get selectedCount => selectedIds.length;

  bool isSelectable(KanjiListItem item) => item.isNew;

  bool isSelected(String cardId) => selectedIds.contains(cardId);

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) {
      loading = true;
      notifyListeners();
    }

    try {
      final cards = await kanjiRepository.getAll();
      final schedules = await progressRepository.getSchedules();
      items = [
        for (final card in cards)
          KanjiListItem(
            card: card,
            schedule: schedules[card.id],
            status: resolver.resolve(schedules[card.id]),
          ),
      ];
      selectedIds.removeWhere(
        (id) => items.every((item) => item.card.id != id || !item.isNew),
      );
    } catch (_) {
      items = const [];
      selectedIds.clear();
    }

    loading = false;
    notifyListeners();
  }

  void enterSelection() {
    if (selecting) return;
    selecting = true;
    selectedIds.clear();
    notifyListeners();
  }

  void exitSelection() {
    if (!selecting && selectedIds.isEmpty) return;
    selecting = false;
    selectedIds.clear();
    notifyListeners();
  }

  void toggleSelected(String cardId) {
    if (!selecting || busy) return;
    KanjiListItem? item;
    for (final candidate in items) {
      if (candidate.card.id == cardId) {
        item = candidate;
        break;
      }
    }
    if (item == null || !isSelectable(item)) return;
    if (!selectedIds.add(cardId)) {
      selectedIds.remove(cardId);
    }
    notifyListeners();
  }

  void selectAllNew() {
    if (!selecting || busy) return;
    selectedIds
      ..clear()
      ..addAll(items.where(isSelectable).map((item) => item.card.id));
    notifyListeners();
  }

  void clearSelection() {
    if (selectedIds.isEmpty) return;
    selectedIds.clear();
    notifyListeners();
  }

  Future<void> markSelectedAsKnown({DateTime? now}) async {
    if (!selecting || selectedIds.isEmpty || busy) return;
    busy = true;
    notifyListeners();
    try {
      final ids = List<String>.from(selectedIds);
      await markAsKnown.markKanjiAsKnownAll(ids, now: now);
      selecting = false;
      selectedIds.clear();
      await load(showLoading: false);
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
