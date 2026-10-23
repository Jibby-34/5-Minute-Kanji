import 'curriculum_entitlement.dart';

/// Local trial progress and the cached full-version entitlement.
///
/// The cache lets the app open offline. The store is asked again whenever it
/// is reachable; this record is not treated as proof of payment by itself.
class CurriculumRecord {
  const CurriculumRecord({
    this.studiedIds = const {},
    this.backfillCompleted = false,
    this.unlocked = false,
    this.subscription = MonthlySubscriptionState.none,
    this.subscriptionExpiresAt,
  });

  final Set<String> studiedIds;

  /// Historical schedules have already been folded into [studiedIds].
  final bool backfillCompleted;

  /// Lifetime non-consumable. This is not the monthly subscription.
  final bool unlocked;

  final MonthlySubscriptionState subscription;

  /// Paid-through date last reported for the monthly subscription.
  final DateTime? subscriptionExpiresAt;

  CurriculumRecord copyWith({
    Set<String>? studiedIds,
    bool? backfillCompleted,
    bool? unlocked,
    MonthlySubscriptionState? subscription,
    DateTime? subscriptionExpiresAt,
    bool clearSubscriptionExpiry = false,
  }) {
    return CurriculumRecord(
      studiedIds: studiedIds ?? this.studiedIds,
      backfillCompleted: backfillCompleted ?? this.backfillCompleted,
      unlocked: unlocked ?? this.unlocked,
      subscription: subscription ?? this.subscription,
      subscriptionExpiresAt: clearSubscriptionExpiry
          ? null
          : subscriptionExpiresAt ?? this.subscriptionExpiresAt,
    );
  }
}

abstract class CurriculumRepository {
  Future<CurriculumRecord> read();

  Future<void> write(CurriculumRecord record);
}

class MemoryCurriculumRepository implements CurriculumRepository {
  MemoryCurriculumRepository({CurriculumRecord? record})
    : record = record ?? const CurriculumRecord();

  CurriculumRecord record;

  @override
  Future<CurriculumRecord> read() async => record;

  @override
  Future<void> write(CurriculumRecord next) async {
    record = next;
  }
}
