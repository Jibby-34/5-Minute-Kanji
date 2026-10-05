import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/card_schedule.dart';
import '../core/models/daily_session_plan.dart';
import '../core/models/onboarding.dart';
import '../core/models/placement.dart';
import '../core/models/progress.dart';
import '../repositories/progress_repository.dart';
import 'legacy_kanji_id_remap.dart';

class SharedPrefsProgressRepository implements ProgressRepository {
  SharedPrefsProgressRepository(this._prefs);

  static const _storageKey = 'progress_v1';
  static const _maxHistoryEntries = 500;

  final SharedPreferences _prefs;

  _ProgressBlob _blob = const _ProgressBlob();
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _blob = _readBlob();
    _loaded = true;
  }

  _ProgressBlob _readBlob() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const _ProgressBlob();
    try {
      final decoded = jsonDecode(raw);
      final map = _asStringKeyMap(decoded);
      if (map == null) return const _ProgressBlob();
      return _ProgressBlob.fromJson(map);
    } catch (_) {
      return const _ProgressBlob();
    }
  }

  Future<void> _persist() async {
    final saved = await _prefs.setString(
      _storageKey,
      jsonEncode(_blob.toJson()),
    );
    if (!saved) {
      throw StateError('Could not persist review progress.');
    }
  }

  @override
  Future<Map<String, CardSchedule>> getSchedules() async {
    await _ensureLoaded();
    return Map.unmodifiable(_blob.schedules);
  }

  @override
  Future<CardSchedule?> getSchedule(String cardId) async {
    await _ensureLoaded();
    return _blob.schedules[cardId];
  }

  @override
  Future<void> saveSchedule(CardSchedule schedule) async {
    await saveSchedules([schedule]);
  }

  @override
  Future<void> saveSchedules(Iterable<CardSchedule> schedules) async {
    final items = schedules.toList();
    if (items.isEmpty) return;
    await _ensureLoaded();
    final next = Map<String, CardSchedule>.from(_blob.schedules);
    for (final schedule in items) {
      next[schedule.cardId] = schedule;
    }
    _blob = _blob.copyWith(schedules: next);
    await _persist();
  }

  @override
  Future<List<ReviewHistoryEntry>> getHistory() async {
    await _ensureLoaded();
    return List.unmodifiable(_blob.history);
  }

  @override
  Future<void> addHistory(ReviewHistoryEntry entry) async {
    await _ensureLoaded();
    final next = [..._blob.history, entry];
    if (next.length > _maxHistoryEntries) {
      next.removeRange(0, next.length - _maxHistoryEntries);
    }
    _blob = _blob.copyWith(history: next);
    await _persist();
  }

  @override
  Future<StreakInfo> getStreak() async {
    await _ensureLoaded();
    return _blob.streak;
  }

  @override
  Future<void> saveStreak(StreakInfo streak) async {
    await _ensureLoaded();
    _blob = _blob.copyWith(streak: streak);
    await _persist();
  }

  @override
  Future<AppSettings> getSettings() async {
    await _ensureLoaded();
    return _blob.settings;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    await _ensureLoaded();
    _blob = _blob.copyWith(settings: settings);
    await _persist();
  }

  @override
  Future<DailyNewKanjiProgress> getDailyNewKanji() async {
    await _ensureLoaded();
    return _blob.dailyNewKanji;
  }

  @override
  Future<void> saveDailyNewKanji(DailyNewKanjiProgress progress) async {
    await _ensureLoaded();
    _blob = _blob.copyWith(dailyNewKanji: progress);
    await _persist();
  }

  @override
  Future<DailySessionPlan> getDailySessionPlan() async {
    await _ensureLoaded();
    return _blob.dailySessionPlan;
  }

  @override
  Future<void> saveDailySessionPlan(DailySessionPlan plan) async {
    await _ensureLoaded();
    _blob = _blob.copyWith(dailySessionPlan: plan);
    await _persist();
  }

  @override
  Future<PlacementProgress> getPlacement() async {
    await _ensureLoaded();
    return _blob.placement;
  }

  @override
  Future<void> savePlacement(PlacementProgress placement) async {
    await _ensureLoaded();
    _blob = _blob.copyWith(placement: placement);
    await _persist();
  }

  @override
  Future<OnboardingProgress> getOnboarding() async {
    await _ensureLoaded();
    return _blob.onboarding;
  }

  @override
  Future<void> saveOnboarding(OnboardingProgress onboarding) async {
    await _ensureLoaded();
    _blob = _blob.copyWith(onboarding: onboarding);
    await _persist();
  }

  @override
  Future<void> seedIfNeeded(List<String> cardIds, {DateTime? now}) async {
    await _ensureLoaded();
    await _migrateLegacyCatalogIfNeeded(cardIds);
    final timestamp = now ?? DateTime.now();
    final next = Map<String, CardSchedule>.from(_blob.schedules);
    var changed = false;
    for (final id in cardIds) {
      if (id.isEmpty) continue;
      if (!next.containsKey(id)) {
        next[id] = CardSchedule.fresh(id, timestamp);
        changed = true;
      }
    }
    if (changed) {
      _blob = _blob.copyWith(schedules: next);
      await _persist();
    }
  }

  /// Moves schedules saved against the previous 250-card ids onto the current
  /// id of the same character.
  ///
  /// The signal is an id that existed only in that catalog (`n5-081` and
  /// above). A library seeded from the N5–N1 list has none of those ids, so
  /// it is stamped and left alone. In-progress placement answers are dropped:
  /// they were chosen from the old pool and would replay against the wrong
  /// kanji. Completed placement and SRS state are kept.
  Future<void> _migrateLegacyCatalogIfNeeded(List<String> cardIds) async {
    if (_blob.kanjiCatalogVersion >= legacyKanjiCatalogVersion) return;

    final currentIds = <String>{
      for (final id in cardIds)
        if (id.isNotEmpty) id,
    };
    final legacy = _blob.schedules.keys.any(
      (id) => legacyKanjiIdRemap.containsKey(id) && !currentIds.contains(id),
    );
    if (!legacy) {
      _blob = _blob.copyWith(kanjiCatalogVersion: legacyKanjiCatalogVersion);
      await _persist();
      return;
    }

    final schedules = <String, CardSchedule>{};
    for (final entry in _blob.schedules.entries) {
      final target = legacyKanjiIdRemap[entry.key] ?? entry.key;
      final schedule = entry.value.withCardId(target);
      final previous = schedules[target];
      if (previous == null || _preferSchedule(schedule, previous)) {
        schedules[target] = schedule;
      }
    }

    final history = [
      for (final entry in _blob.history)
        entry.withCardId(legacyKanjiIdRemap[entry.cardId] ?? entry.cardId),
    ];

    final plan = _blob.dailySessionPlan;
    final seen = <String>{};
    final planIds = <String>[];
    for (final id in plan.cardIds) {
      final target = legacyKanjiIdRemap[id] ?? id;
      if (target.isEmpty || !seen.add(target)) continue;
      planIds.add(target);
    }

    _blob = _blob.copyWith(
      schedules: schedules,
      history: history,
      dailySessionPlan: DailySessionPlan(
        studyDate: plan.studyDate,
        budgetMinutes: plan.budgetMinutes,
        newKanjiPerDay: plan.newKanjiPerDay,
        startOfDay: plan.startOfDay,
        cardIds: planIds,
        completed: plan.completed,
      ),
      placement: PlacementProgress(completed: _blob.placement.completed),
      kanjiCatalogVersion: legacyKanjiCatalogVersion,
    );
    await _persist();
  }

  /// When two old ids land on one new id, keep the schedule that has actually
  /// been studied.
  bool _preferSchedule(CardSchedule candidate, CardSchedule existing) {
    if (candidate.reviewCount != existing.reviewCount) {
      return candidate.reviewCount > existing.reviewCount;
    }
    return candidate.state != CardLearningState.newCard &&
        existing.state == CardLearningState.newCard;
  }
}

class _ProgressBlob {
  const _ProgressBlob({
    this.schedules = const {},
    this.history = const [],
    this.streak = StreakInfo.empty,
    this.settings = const AppSettings(),
    this.dailyNewKanji = DailyNewKanjiProgress.empty,
    this.dailySessionPlan = DailySessionPlan.empty,
    this.placement = PlacementProgress.empty,
    this.onboarding = OnboardingProgress.empty,
    this.kanjiCatalogVersion = 0,
  });

  final Map<String, CardSchedule> schedules;
  final List<ReviewHistoryEntry> history;
  final StreakInfo streak;
  final AppSettings settings;
  final DailyNewKanjiProgress dailyNewKanji;
  final DailySessionPlan dailySessionPlan;
  final PlacementProgress placement;
  final OnboardingProgress onboarding;

  /// 0 is the previous 250-card catalog. [legacyKanjiCatalogVersion] is the
  /// N5–N1 list, after any id remap has run.
  final int kanjiCatalogVersion;

  _ProgressBlob copyWith({
    Map<String, CardSchedule>? schedules,
    List<ReviewHistoryEntry>? history,
    StreakInfo? streak,
    AppSettings? settings,
    DailyNewKanjiProgress? dailyNewKanji,
    DailySessionPlan? dailySessionPlan,
    PlacementProgress? placement,
    OnboardingProgress? onboarding,
    int? kanjiCatalogVersion,
  }) {
    return _ProgressBlob(
      schedules: schedules ?? this.schedules,
      history: history ?? this.history,
      streak: streak ?? this.streak,
      settings: settings ?? this.settings,
      dailyNewKanji: dailyNewKanji ?? this.dailyNewKanji,
      dailySessionPlan: dailySessionPlan ?? this.dailySessionPlan,
      placement: placement ?? this.placement,
      onboarding: onboarding ?? this.onboarding,
      kanjiCatalogVersion: kanjiCatalogVersion ?? this.kanjiCatalogVersion,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schedules': {
        for (final entry in schedules.entries) entry.key: entry.value.toJson(),
      },
      'history': history.map((e) => e.toJson()).toList(),
      'streak': streak.toJson(),
      'settings': settings.toJson(),
      'dailyNewKanji': dailyNewKanji.toJson(),
      'dailySessionPlan': dailySessionPlan.toJson(),
      'placement': placement.toJson(),
      'onboarding': onboarding.toJson(),
      'kanjiCatalogVersion': kanjiCatalogVersion,
    };
  }

  factory _ProgressBlob.fromJson(Map<String, dynamic> json) {
    final rawSchedules = _asStringKeyMap(json['schedules']);
    final schedules = <String, CardSchedule>{};
    if (rawSchedules != null) {
      for (final entry in rawSchedules.entries) {
        final value = _asStringKeyMap(entry.value);
        if (value == null) continue;
        final schedule = CardSchedule.fromJson(value);
        if (schedule == null || schedule.cardId != entry.key) continue;
        schedules[entry.key] = schedule;
      }
    }

    final rawHistory = json['history'];
    final history = <ReviewHistoryEntry>[];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        final map = _asStringKeyMap(item);
        if (map == null) continue;
        final entry = ReviewHistoryEntry.fromJson(map);
        if (entry != null) history.add(entry);
      }
    }

    return _ProgressBlob(
      schedules: schedules,
      history: history,
      streak: StreakInfo.fromJson(_asStringKeyMap(json['streak'])),
      settings: AppSettings.fromJson(_asStringKeyMap(json['settings'])),
      dailyNewKanji: DailyNewKanjiProgress.fromJson(
        _asStringKeyMap(json['dailyNewKanji']),
      ),
      dailySessionPlan: DailySessionPlan.fromJson(
        _asStringKeyMap(json['dailySessionPlan']),
      ),
      placement: PlacementProgress.fromJson(_asStringKeyMap(json['placement'])),
      onboarding: OnboardingProgress.fromJson(
        _asStringKeyMap(json['onboarding']),
      ),
      kanjiCatalogVersion: (json['kanjiCatalogVersion'] as num?)?.toInt() ?? 0,
    );
  }
}

Map<String, dynamic>? _asStringKeyMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}
