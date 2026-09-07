import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/card_schedule.dart';
import '../core/models/progress.dart';
import '../repositories/progress_repository.dart';

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
  Future<void> seedIfNeeded(List<String> cardIds, {DateTime? now}) async {
    await _ensureLoaded();
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
}

class _ProgressBlob {
  const _ProgressBlob({
    this.schedules = const {},
    this.history = const [],
    this.streak = StreakInfo.empty,
    this.settings = const AppSettings(),
    this.dailyNewKanji = DailyNewKanjiProgress.empty,
  });

  final Map<String, CardSchedule> schedules;
  final List<ReviewHistoryEntry> history;
  final StreakInfo streak;
  final AppSettings settings;
  final DailyNewKanjiProgress dailyNewKanji;

  _ProgressBlob copyWith({
    Map<String, CardSchedule>? schedules,
    List<ReviewHistoryEntry>? history,
    StreakInfo? streak,
    AppSettings? settings,
    DailyNewKanjiProgress? dailyNewKanji,
  }) {
    return _ProgressBlob(
      schedules: schedules ?? this.schedules,
      history: history ?? this.history,
      streak: streak ?? this.streak,
      settings: settings ?? this.settings,
      dailyNewKanji: dailyNewKanji ?? this.dailyNewKanji,
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
