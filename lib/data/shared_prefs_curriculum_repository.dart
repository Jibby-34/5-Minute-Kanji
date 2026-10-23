import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/curriculum/curriculum_entitlement.dart';
import '../services/curriculum/curriculum_repository.dart';

class SharedPrefsCurriculumRepository implements CurriculumRepository {
  SharedPrefsCurriculumRepository(this._prefs);

  static const storageKey = 'curriculum_v1';

  final SharedPreferences _prefs;

  @override
  Future<CurriculumRecord> read() async {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const CurriculumRecord();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const CurriculumRecord();
      final ids = <String>{};
      final rawIds = decoded['studiedIds'];
      if (rawIds is List) {
        for (final id in rawIds) {
          if (id is String && id.isNotEmpty) ids.add(id);
        }
      }
      return CurriculumRecord(
        studiedIds: ids,
        backfillCompleted: decoded['backfillCompleted'] as bool? ?? false,
        unlocked: decoded['unlocked'] as bool? ?? false,
        subscription: _subscription(decoded['subscription']),
        subscriptionExpiresAt: _expiry(decoded['subscriptionExpiresAt']),
      );
    } catch (_) {
      return const CurriculumRecord();
    }
  }

  @override
  Future<void> write(CurriculumRecord record) async {
    final saved = await _prefs.setString(
      storageKey,
      jsonEncode({
        'studiedIds': record.studiedIds.toList()..sort(),
        'backfillCompleted': record.backfillCompleted,
        'unlocked': record.unlocked,
        'subscription': record.subscription.name,
        'subscriptionExpiresAt': record.subscriptionExpiresAt
            ?.toUtc()
            .toIso8601String(),
      }),
    );
    if (!saved) {
      throw StateError('Could not persist curriculum progress.');
    }
  }
}

MonthlySubscriptionState _subscription(Object? raw) {
  if (raw is! String) return MonthlySubscriptionState.none;
  for (final state in MonthlySubscriptionState.values) {
    if (state.name == raw) return state;
  }
  return MonthlySubscriptionState.none;
}

DateTime? _expiry(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
