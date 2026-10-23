import 'curriculum_entitlement.dart';
import 'curriculum_products.dart';

/// Localized store product. [price] comes from the platform, not a fixed USD amount.
class CurriculumProduct {
  const CurriculumProduct({
    required this.id,
    required this.price,
    required this.raw,
    this.billingPeriod,
  });

  final String id;
  final String price;

  /// Platform product details needed to start a purchase.
  final Object raw;

  /// ISO-8601 period for a subscription base plan, such as `P1M`.
  final String? billingPeriod;
}

class CurriculumCatalog {
  const CurriculumCatalog({this.lifetime, this.monthly});

  final CurriculumProduct? lifetime;
  final CurriculumProduct? monthly;

  bool get isEmpty => lifetime == null && monthly == null;
}

enum CurriculumPurchaseStatus { pending, purchased, restored, canceled, error }

class CurriculumPurchaseUpdate {
  const CurriculumPurchaseUpdate({
    required this.productId,
    required this.status,
    this.purchaseId,
    this.pendingComplete = false,
    this.verificationData = '',
    this.errorCode,
    this.errorMessage,
    this.raw,
    this.subscriptionState,
    this.subscriptionExpiresAt,
  });

  final String productId;
  final CurriculumPurchaseStatus status;
  final String? purchaseId;
  final bool pendingComplete;
  final String verificationData;
  final String? errorCode;
  final String? errorMessage;

  /// Platform purchase object passed back to [CurriculumBilling.complete].
  final Object? raw;

  /// Set for a monthly purchase when the store adapter could classify it.
  final MonthlySubscriptionState? subscriptionState;
  final DateTime? subscriptionExpiresAt;

  bool get isFullCurriculum => productId == fullCurriculumUnlock;

  bool get isMonthly => productId == fullCurriculumMonthly;

  bool get grantsEntitlement {
    if (!isFullCurriculum) return false;
    if (status != CurriculumPurchaseStatus.purchased &&
        status != CurriculumPurchaseStatus.restored) {
      return false;
    }
    return verificationData.trim().isNotEmpty;
  }

  /// A verified monthly purchase that should unlock new kanji.
  ///
  /// Pending, canceled, expired, and refunded updates do not.
  bool get grantsSubscription {
    if (!isMonthly) return false;
    if (status != CurriculumPurchaseStatus.purchased &&
        status != CurriculumPurchaseStatus.restored) {
      return false;
    }
    if (verificationData.trim().isEmpty) return false;
    final state = subscriptionState;
    if (state == MonthlySubscriptionState.expired ||
        state == MonthlySubscriptionState.refunded ||
        state == MonthlySubscriptionState.none) {
      return false;
    }
    return true;
  }

  bool get isCancellation {
    if (status == CurriculumPurchaseStatus.canceled) return true;
    if (status != CurriculumPurchaseStatus.error) return false;
    final code = (errorCode ?? '').toLowerCase();
    final message = (errorMessage ?? '').toLowerCase();
    return code.contains('cancel') || code == '2' || message.contains('cancel');
  }
}

/// Result of a silent ownership check.
///
/// [unavailable] keeps the cached entitlement. It is not the same as
/// [notOwned].
enum EntitlementQueryResult { owned, notOwned, unavailable }

/// Lifetime and monthly answers from one store query.
///
/// A null subscription ([subscriptionKnown] false) leaves the cached
/// subscription alone. [EntitlementQueryResult.unavailable] does the same
/// for the lifetime flag.
class StoreEntitlementSnapshot {
  const StoreEntitlementSnapshot({
    required this.lifetime,
    this.subscriptionKnown = false,
    this.subscription = MonthlySubscriptionState.none,
    this.subscriptionExpiresAt,
  });

  final EntitlementQueryResult lifetime;
  final bool subscriptionKnown;
  final MonthlySubscriptionState subscription;
  final DateTime? subscriptionExpiresAt;
}

/// Store port. Tests use a fake; the app uses the platform billing plugin.
abstract class CurriculumBilling {
  Future<bool> isAvailable();

  Future<CurriculumProduct?> loadProduct();

  /// Lifetime and monthly products from one store query.
  ///
  /// The default asks only for the lifetime product so existing fakes keep
  /// working. The store adapter loads both.
  Future<CurriculumCatalog> loadCatalog() async {
    return CurriculumCatalog(lifetime: await loadProduct());
  }

  /// Starts the native purchase sheet. The entitlement is decided later on
  /// [purchaseUpdates], never by this method returning.
  Future<bool> startPurchase(CurriculumProduct product);

  Future<void> restorePurchases();

  /// Android re-queries owned purchases. iOS returns [EntitlementQueryResult.unavailable]
  /// so a silent check cannot clear a purchase; restoration uses [restorePurchases].
  Future<EntitlementQueryResult> queryEntitlement();

  /// Lifetime query plus the monthly subscription, when the store can answer.
  ///
  /// The default keeps the previous lifetime-only check and does not touch a
  /// cached subscription.
  Future<StoreEntitlementSnapshot> queryStoreEntitlement() async {
    return StoreEntitlementSnapshot(lifetime: await queryEntitlement());
  }

  Stream<List<CurriculumPurchaseUpdate>> get purchaseUpdates;

  Future<void> complete(CurriculumPurchaseUpdate update);
}

/// Used when the platform billing plugin is not wired up, including tests
/// that build the app shell.
class UnavailableCurriculumBilling implements CurriculumBilling {
  const UnavailableCurriculumBilling();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<CurriculumProduct?> loadProduct() async => null;

  @override
  Future<CurriculumCatalog> loadCatalog() async => const CurriculumCatalog();

  @override
  Future<bool> startPurchase(CurriculumProduct product) async => false;

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<EntitlementQueryResult> queryEntitlement() async {
    return EntitlementQueryResult.unavailable;
  }

  @override
  Future<StoreEntitlementSnapshot> queryStoreEntitlement() async {
    return const StoreEntitlementSnapshot(
      lifetime: EntitlementQueryResult.unavailable,
    );
  }

  @override
  Stream<List<CurriculumPurchaseUpdate>> get purchaseUpdates =>
      const Stream<List<CurriculumPurchaseUpdate>>.empty();

  @override
  Future<void> complete(CurriculumPurchaseUpdate update) async {}
}
