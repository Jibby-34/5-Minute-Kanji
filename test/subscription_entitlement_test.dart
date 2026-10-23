import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/data/shared_prefs_curriculum_repository.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_access.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_analytics.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_billing.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_entitlement.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_products.dart';
import 'package:fiveminutekanji/services/curriculum/curriculum_repository.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);
  final later = now.add(const Duration(days: 20));
  final earlier = now.subtract(const Duration(days: 3));

  CurriculumEntitlement entitlement({
    bool lifetime = false,
    MonthlySubscriptionState subscription = MonthlySubscriptionState.none,
    DateTime? expiresAt,
  }) {
    return CurriculumEntitlement(
      lifetime: lifetime,
      subscription: subscription,
      subscriptionExpiresAt: expiresAt,
    );
  }

  test('no purchase has no full access', () {
    expect(entitlement().hasFullAccess(now), isFalse);
  });

  test('lifetime alone unlocks the curriculum', () {
    expect(entitlement(lifetime: true).hasFullAccess(now), isTrue);
    expect(
      entitlement(lifetime: true).subscriptionGrantsAccess(now),
      isFalse,
    );
  });

  test('an active monthly subscription unlocks the curriculum', () {
    expect(
      entitlement(
        subscription: MonthlySubscriptionState.active,
        expiresAt: later,
      ).hasFullAccess(now),
      isTrue,
    );
  });

  test('an expired monthly subscription locks new kanji', () {
    expect(
      entitlement(
        subscription: MonthlySubscriptionState.expired,
        expiresAt: earlier,
      ).hasFullAccess(now),
      isFalse,
    );
    expect(
      entitlement(
        subscription: MonthlySubscriptionState.active,
        expiresAt: earlier,
      ).hasFullAccess(now),
      isFalse,
    );
  });

  test('grace period stays active after the paid date', () {
    expect(
      entitlement(
        subscription: MonthlySubscriptionState.gracePeriod,
        expiresAt: earlier,
      ).hasFullAccess(now),
      isTrue,
    );
  });

  test('billing retry stays active', () {
    expect(
      entitlement(
        subscription: MonthlySubscriptionState.billingRetry,
        expiresAt: earlier,
      ).hasFullAccess(now),
      isTrue,
    );
  });

  test('lifetime wins over an active, expired, or refunded subscription', () {
    for (final state in [
      MonthlySubscriptionState.active,
      MonthlySubscriptionState.expired,
      MonthlySubscriptionState.refunded,
    ]) {
      final decision = entitlement(
        lifetime: true,
        subscription: state,
        expiresAt: earlier,
      );
      expect(decision.hasFullAccess(now), isTrue, reason: state.name);
    }
  });

  test('a refunded subscription does not unlock the curriculum', () {
    expect(
      entitlement(
        subscription: MonthlySubscriptionState.refunded,
        expiresAt: later,
      ).hasFullAccess(now),
      isFalse,
    );
  });

  test('offline cache follows the saved expiry without asking the store', () {
    final cached = entitlement(
      subscription: MonthlySubscriptionState.active,
      expiresAt: later,
    );
    expect(cached.hasFullAccess(now), isTrue);
    expect(cached.hasFullAccess(later.add(const Duration(minutes: 1))), isFalse);
  });

  test('Play grace is a returned subscription past its paid period', () {
    final purchaseTime = now.subtract(const Duration(days: 40));
    final decision = androidMonthlyState(purchaseTime: purchaseTime, now: now);
    expect(decision.state, MonthlySubscriptionState.gracePeriod);
    expect(
      entitlement(
        subscription: decision.state,
        expiresAt: decision.expiresAt,
      ).hasFullAccess(now),
      isTrue,
    );

    final current = androidMonthlyState(
      purchaseTime: now.subtract(const Duration(days: 10)),
      now: now,
    );
    expect(current.state, MonthlySubscriptionState.active);
    expect(current.expiresAt!.isAfter(now), isTrue);
  });

  test('a one month billing period lands on the same day next month', () {
    expect(
      addBillingPeriod(DateTime.utc(2026, 6, 15, 8), 'P1M'),
      DateTime.utc(2026, 7, 15, 8),
    );
  });

  test('StoreKit current entitlements past expiry count as billing retry', () {
    final decision = appleMonthlyState(
      now: now,
      expiresAt: earlier,
      fromCurrentEntitlements: true,
    );
    expect(decision.state, MonthlySubscriptionState.billingRetry);
    expect(
      entitlement(
        subscription: decision.state,
        expiresAt: decision.expiresAt,
      ).hasFullAccess(now),
      isTrue,
    );

    final lapsed = appleMonthlyState(now: now, expiresAt: earlier);
    expect(lapsed.state, MonthlySubscriptionState.expired);

    final refunded = appleMonthlyState(
      now: now,
      expiresAt: later,
      revocationDate: now,
    );
    expect(refunded.state, MonthlySubscriptionState.refunded);
  });

  test('cached subscription survives restart and expiry locks only new kanji', () async {
    final studied = {for (var i = 0; i < 50; i++) 'done-$i'};
    final repository = MemoryCurriculumRepository(
      record: CurriculumRecord(
        studiedIds: studied,
        backfillCompleted: true,
        subscription: MonthlySubscriptionState.active,
        subscriptionExpiresAt: later,
      ),
    );
    var clock = now;
    final access = CurriculumAccess(
      progressRepository: MemoryProgressRepository(),
      repository: repository,
      billing: const UnavailableCurriculumBilling(),
      clock: () => clock,
    );
    await access.ensureLoaded();
    await pumpEventQueue();

    expect(access.lifetimeOwned, isFalse);
    expect(access.unlocked, isTrue);
    expect(access.storeUnavailable, isTrue);
    expect(
      await access.tryRecordStudy('new-one'),
      isA<StudyRecordResult>().having((result) => result.allowed, 'allowed', isTrue),
    );

    clock = later.add(const Duration(days: 1));
    await access.refresh();

    expect(access.unlocked, isFalse);
    expect(access.studiedIds, contains('new-one'));
    expect(repository.record.studiedIds, containsAll(studied));
    final blocked = await access.tryRecordStudy('past-the-cap');
    expect(blocked.allowed, isFalse);
    expect(
      (await access.tryRecordStudy('done-0')).newlyRecorded,
      isFalse,
    );
    expect(repository.record.studiedIds, isNot(contains('past-the-cap')));
  });

  test('monthly purchase, pending, and lifetime together follow the store', () async {
    final billing = _Billing(
      lifetime: const CurriculumProduct(
        id: fullCurriculumUnlock,
        price: r'CA$79.99',
        raw: Object(),
      ),
      monthly: const CurriculumProduct(
        id: fullCurriculumMonthly,
        price: r'CA$8.99',
        raw: Object(),
        billingPeriod: 'P1M',
      ),
    );
    final events = _RecordingAnalytics();
    final access = CurriculumAccess(
      progressRepository: MemoryProgressRepository(),
      repository: MemoryCurriculumRepository(
        record: const CurriculumRecord(backfillCompleted: true),
      ),
      billing: billing,
      analytics: events,
      clock: () => now,
    );
    await access.ensureLoaded();
    await access.buyMonthly();
    expect(events.started, [fullCurriculumMonthly]);
    expect(access.unlocked, isFalse);

    billing.emit(
      CurriculumPurchaseUpdate(
        productId: fullCurriculumMonthly,
        status: CurriculumPurchaseStatus.pending,
        pendingComplete: false,
        verificationData: '',
      ),
    );
    await pumpEventQueue();
    expect(access.unlocked, isFalse);
    expect(access.purchaseMessage, 'Purchase pending approval.');

    billing.emit(
      CurriculumPurchaseUpdate(
        productId: fullCurriculumMonthly,
        status: CurriculumPurchaseStatus.purchased,
        verificationData: 'signed-receipt',
        subscriptionState: MonthlySubscriptionState.active,
        subscriptionExpiresAt: later,
      ),
    );
    await pumpEventQueue();
    expect(access.unlocked, isTrue);
    expect(access.lifetimeOwned, isFalse);
    expect(events.succeeded, [fullCurriculumMonthly]);

    await access.buy();
    billing.emit(
      const CurriculumPurchaseUpdate(
        productId: fullCurriculumUnlock,
        status: CurriculumPurchaseStatus.purchased,
        verificationData: 'signed-receipt',
      ),
    );
    await pumpEventQueue();
    expect(access.lifetimeOwned, isTrue);
    expect(access.promptCancelMonthly, isTrue);
    expect(access.notice, CurriculumNotice.cancelMonthly);
    expect(access.purchaseMessage, contains('Cancel the monthly subscription'));
  });

  test('a lifetime refund query does not clear an active subscription', () async {
    final billing = _Billing()
      ..snapshot = const StoreEntitlementSnapshot(
        lifetime: EntitlementQueryResult.notOwned,
      );
    final access = CurriculumAccess(
      progressRepository: MemoryProgressRepository(),
      repository: MemoryCurriculumRepository(
        record: CurriculumRecord(
          backfillCompleted: true,
          subscription: MonthlySubscriptionState.active,
          subscriptionExpiresAt: later,
        ),
      ),
      billing: billing,
      clock: () => now,
    );
    await access.ensureLoaded();
    await pumpEventQueue();

    expect(access.lifetimeOwned, isFalse);
    expect(access.subscriptionActive, isTrue);
    expect(access.unlocked, isTrue);
  });

  test('subscription cache is written and read back', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = SharedPrefsCurriculumRepository(prefs);
    await repository.write(
      CurriculumRecord(
        backfillCompleted: true,
        unlocked: true,
        subscription: MonthlySubscriptionState.gracePeriod,
        subscriptionExpiresAt: earlier,
      ),
    );
    final loaded = await SharedPrefsCurriculumRepository(prefs).read();
    expect(loaded.unlocked, isTrue);
    expect(loaded.subscription, MonthlySubscriptionState.gracePeriod);
    expect(loaded.subscriptionExpiresAt, earlier);
  });
}

class _RecordingAnalytics extends CurriculumAnalytics {
  final started = <String>[];
  final succeeded = <String>[];

  @override
  void purchaseStarted(String productId) => started.add(productId);

  @override
  void purchaseSucceeded(String productId) => succeeded.add(productId);
}

class _Billing implements CurriculumBilling {
  _Billing({this.lifetime, this.monthly});

  final _updates = StreamController<List<CurriculumPurchaseUpdate>>.broadcast();
  final CurriculumProduct? lifetime;
  final CurriculumProduct? monthly;
  StoreEntitlementSnapshot snapshot = const StoreEntitlementSnapshot(
    lifetime: EntitlementQueryResult.unavailable,
  );

  void emit(CurriculumPurchaseUpdate update) => _updates.add([update]);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<CurriculumProduct?> loadProduct() async => null;

  @override
  Future<CurriculumCatalog> loadCatalog() async {
    return CurriculumCatalog(lifetime: lifetime, monthly: monthly);
  }

  @override
  Future<bool> startPurchase(CurriculumProduct product) async => true;

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<EntitlementQueryResult> queryEntitlement() async => snapshot.lifetime;

  @override
  Future<StoreEntitlementSnapshot> queryStoreEntitlement() async => snapshot;

  @override
  Stream<List<CurriculumPurchaseUpdate>> get purchaseUpdates => _updates.stream;

  @override
  Future<void> complete(CurriculumPurchaseUpdate update) async {}
}
