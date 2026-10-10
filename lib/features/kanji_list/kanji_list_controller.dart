import 'package:flutter/foundation.dart';

import '../../core/models/card_schedule.dart';
import '../../core/models/curriculum_mode.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/kanji_status.dart';
import '../../repositories/kanji_repository.dart';
import '../../repositories/progress_repository.dart';
import '../../services/curriculum_priority_service.dart';
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

/// Flat list orders. The JLPT option keeps the sectioned overview.
enum KanjiListOrdering {
  recommended,
  frequency,
  difficulty,
  jlpt,
  learned,
  notEncountered;

  static const displayOptions = <KanjiListOrdering>[
    recommended,
    frequency,
    difficulty,
    jlpt,
  ];

  String get label => switch (this) {
    KanjiListOrdering.recommended => 'Learning Path',
    KanjiListOrdering.frequency => 'Frequency',
    KanjiListOrdering.difficulty => 'Difficulty',
    KanjiListOrdering.jlpt => 'JLPT',
    KanjiListOrdering.learned => 'Learned',
    KanjiListOrdering.notEncountered => 'New',
  };
}

/// Learning-status filter for the list. Uses [KanjiProgressStatus], not tile color.
enum KanjiListStatusFilter {
  all,
  learning,
  mastered;

  String get label => switch (this) {
    KanjiListStatusFilter.all => 'All',
    KanjiListStatusFilter.learning => 'Learning',
    KanjiListStatusFilter.mastered => 'Mastered',
  };
}

/// Folds case and katakana so reading search matches hiragana or katakana.
String foldForSearch(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    if (rune >= 0x30A1 && rune <= 0x30F6) {
      buffer.writeCharCode(rune - 0x60);
    } else if (rune == 0x30FB || rune == 0x00B7) {
      continue;
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Search blob for one card: character, meanings, readings, and mnemonic.
String kanjiSearchKey(KanjiCard card) {
  return [
    card.character,
    card.meaning,
    card.keyword,
    card.mnemonic,
    ...card.onyomi,
    ...card.kunyomi,
  ].map(foldForSearch).join('\n');
}

bool kanjiMatchesStatus(
  KanjiProgressStatus status,
  KanjiListStatusFilter filter,
) {
  return switch (filter) {
    KanjiListStatusFilter.all => true,
    KanjiListStatusFilter.learning => status == KanjiProgressStatus.learning,
    KanjiListStatusFilter.mastered => status == KanjiProgressStatus.mastered,
  };
}

/// Sorts the kanji list with the same curriculum engine the study session uses.
///
/// [KanjiListOrdering.learned] and [KanjiListOrdering.notEncountered] are list
/// status orders. They do not recalculate curriculum priority.
List<KanjiListItem> orderKanjiListItems({
  required List<KanjiListItem> items,
  required KanjiListOrdering ordering,
  required CurriculumPriorityService curriculum,
  Set<String>? knownCardIds,
}) {
  final known =
      knownCardIds ??
      {
        for (final item in items)
          if (item.status != KanjiProgressStatus.notEncountered) item.card.id,
      };
  final ordered = List<KanjiListItem>.from(items);
  switch (ordering) {
    case KanjiListOrdering.learned:
      ordered.sort((a, b) {
        final byStatus = _statusRank(
          a.status,
          learnedFirst: true,
        ).compareTo(_statusRank(b.status, learnedFirst: true));
        if (byStatus != 0) return byStatus;
        return a.card.id.compareTo(b.card.id);
      });
    case KanjiListOrdering.notEncountered:
      ordered.sort((a, b) {
        final byStatus = _statusRank(
          a.status,
          learnedFirst: false,
        ).compareTo(_statusRank(b.status, learnedFirst: false));
        if (byStatus != 0) return byStatus;
        return a.card.id.compareTo(b.card.id);
      });
    case KanjiListOrdering.recommended:
    case KanjiListOrdering.frequency:
    case KanjiListOrdering.jlpt:
    case KanjiListOrdering.difficulty:
      ordered.sort(
        (a, b) => curriculum.compare(
          a.card,
          b.card,
          mode: _curriculumMode(ordering),
          knownCardIds: known,
        ),
      );
  }
  return ordered;
}

CurriculumMode _curriculumMode(KanjiListOrdering ordering) {
  return switch (ordering) {
    KanjiListOrdering.recommended => CurriculumMode.recommended,
    KanjiListOrdering.frequency => CurriculumMode.frequency,
    KanjiListOrdering.jlpt => CurriculumMode.jlpt,
    KanjiListOrdering.difficulty => CurriculumMode.difficulty,
    KanjiListOrdering.learned ||
    KanjiListOrdering.notEncountered => CurriculumMode.recommended,
  };
}

int _statusRank(KanjiProgressStatus status, {required bool learnedFirst}) {
  return switch (status) {
    KanjiProgressStatus.mastered => learnedFirst ? 0 : 2,
    KanjiProgressStatus.learning => 1,
    KanjiProgressStatus.notEncountered => learnedFirst ? 2 : 0,
  };
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
  KanjiListOrdering ordering = KanjiListOrdering.recommended;
  KanjiListStatusFilter statusFilter = KanjiListStatusFilter.all;
  String query = '';
  List<KanjiListItem> items = const [];
  final Set<String> selectedIds = {};

  /// N5 starts open. Other levels stay closed until the learner expands them.
  final Set<JlptLevel> expandedLevels = {JlptLevel.n5};

  CurriculumPriorityService? _curriculum;
  Map<String, String> _searchKeys = const {};
  List<KanjiListItem>? _cachedOrdered;
  KanjiListOrdering? _cachedOrdering;

  /// While a search is active, section expansion is temporary and does not
  /// replace [expandedLevels].
  Set<JlptLevel>? _searchSectionExpansion;

  bool get groupsByJlpt => ordering == KanjiListOrdering.jlpt;

  bool get searchActive => query.trim().isNotEmpty;

  /// Kanji in the order selected on the list, before search and status filters.
  List<KanjiListItem> get orderedItems {
    final cached = _cachedOrdered;
    if (cached != null && _cachedOrdering == ordering) return cached;
    final curriculum = _curriculum;
    if (curriculum == null) return items;
    final ordered = orderKanjiListItems(
      items: items,
      ordering: ordering,
      curriculum: curriculum,
    );
    _cachedOrdered = ordered;
    _cachedOrdering = ordering;
    return ordered;
  }

  /// [orderedItems] limited to the current search and learning-status filter.
  List<KanjiListItem> get visibleItems {
    final ordered = orderedItems;
    if (!searchActive && statusFilter == KanjiListStatusFilter.all) {
      return ordered;
    }
    return [
      for (final item in ordered)
        if (_isVisible(item)) item,
    ];
  }

  int get matchCount => visibleItems.length;

  List<KanjiListSection> get sections {
    final source = groupsByJlpt ? orderedItems : items;
    if (!searchActive && statusFilter == KanjiListStatusFilter.all) {
      return groupKanjiByJlpt(source);
    }
    return groupKanjiByJlpt([
      for (final item in source)
        if (_isVisible(item)) item,
    ]);
  }

  int get selectedCount => selectedIds.length;

  bool isSectionExpanded(JlptLevel level) {
    if (searchActive) {
      final override = _searchSectionExpansion;
      if (override == null) return true;
      return override.contains(level);
    }
    return expandedLevels.contains(level);
  }

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
      _curriculum = CurriculumPriorityService(cards);
      _searchKeys = {
        for (final item in items) item.card.id: kanjiSearchKey(item.card),
      };
      _cachedOrdered = null;
      selectedIds.removeWhere(
        (id) => items.every((item) => item.card.id != id || !item.isNew),
      );
    } catch (_) {
      items = const [];
      _curriculum = null;
      _searchKeys = const {};
      _cachedOrdered = null;
      selectedIds.clear();
    }

    loading = false;
    notifyListeners();
  }

  void setOrdering(KanjiListOrdering value) {
    if (ordering == value) return;
    ordering = value;
    notifyListeners();
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    _searchSectionExpansion = null;
    notifyListeners();
  }

  void setStatusFilter(KanjiListStatusFilter value) {
    if (statusFilter == value) return;
    statusFilter = value;
    notifyListeners();
  }

  void toggleSection(JlptLevel level) {
    if (searchActive) {
      final current = _searchSectionExpansion ?? JlptLevel.sectionOrder.toSet();
      if (!current.remove(level)) current.add(level);
      _searchSectionExpansion = current;
    } else if (!expandedLevels.remove(level)) {
      expandedLevels.add(level);
    }
    notifyListeners();
  }

  bool _isVisible(KanjiListItem item) {
    if (!kanjiMatchesStatus(item.status, statusFilter)) return false;
    if (!searchActive) return true;
    final key = _searchKeys[item.card.id] ?? kanjiSearchKey(item.card);
    return key.contains(foldForSearch(query.trim()));
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
