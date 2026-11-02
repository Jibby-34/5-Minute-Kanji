import '../analytics/analytics_service.dart';
import 'curriculum_products.dart';

/// Purchase events forwarded to [AnalyticsService].
///
/// `purchase_completed` and `purchase_restored` are sent only after the store
/// confirms a verified transaction, and the same transaction key is ignored
/// the second time. Tapping restore, opening the paywall, and starting
/// checkout do not count as a completed purchase. User cancellation is not
/// reported as `purchase_failed`.
class CurriculumAnalytics {
  CurriculumAnalytics({AnalyticsService? events})
    : events = events ?? AnalyticsService();

  final AnalyticsService events;
  final Set<String> _reportedFailures = {};

  void paywallViewed({String placement = 'unknown'}) {
    events.paywallViewed(placement: placement);
  }

  void purchaseStarted(String productId) {
    _reportedFailures.removeWhere((entry) => entry.startsWith('$productId|'));
    events.purchaseStarted(
      productId: productId,
      purchaseType: purchaseTypeFor(productId),
    );
  }

  void purchaseSucceeded(String productId, {String? transactionKey}) {
    if (!_claim(transactionKey, fallback: 'purchase:$productId')) return;
    events.purchaseCompleted(
      productId: productId,
      purchaseType: purchaseTypeFor(productId),
    );
  }

  void purchaseRestored(String productId, {String? transactionKey}) {
    if (!_claim(transactionKey, fallback: 'restore:$productId')) return;
    events.purchaseRestored(
      productId: productId,
      purchaseType: purchaseTypeFor(productId),
    );
  }

  void purchaseFailed(String productId, {required String errorCategory}) {
    final key = '$productId|$errorCategory';
    if (!_reportedFailures.add(key)) return;
    events.purchaseFailed(
      productId: productId,
      purchaseType: purchaseTypeFor(productId),
      errorCategory: errorCategory,
    );
  }

  /// The shopper backed out. This is not a failed purchase.
  void purchaseCancelled(String productId) {}

  /// The restore button was tapped. A successful restore is reported later,
  /// from the verified store update.
  void restoreTapped() {}

  bool _claim(String? transactionKey, {required String fallback}) {
    return events.claimTransaction(transactionKey ?? fallback);
  }
}

/// Store transaction identity used to drop repeated purchase-stream events.
///
/// A missing purchase id falls back to the product and, for a subscription,
/// the expiry. The raw receipt is not used.
String purchaseTransactionKey({
  required String productId,
  String? purchaseId,
  DateTime? expiresAt,
}) {
  final id = purchaseId?.trim();
  if (id != null && id.isNotEmpty) return 'id:$id';
  final expiry = expiresAt?.toUtc().toIso8601String() ?? '';
  return 'fallback:$productId:$expiry';
}

/// `lifetime` or `subscription` for the products this app already sells.
String purchaseTypeFor(String productId) {
  if (productId == fullCurriculumMonthly) return 'subscription';
  if (productId == fullCurriculumUnlock) return 'lifetime';
  return 'unknown';
}

/// A short failure bucket. Store messages are not included.
String purchaseErrorCategory(String? errorCode) {
  final code = (errorCode ?? '').toLowerCase();
  if (code.contains('network') || code.contains('timeout')) return 'network';
  if (code.contains('billing')) return 'billing_unavailable';
  if (code.contains('item_unavailable') ||
      code.contains('product') ||
      code.contains('sku')) {
    return 'product_unavailable';
  }
  if (code.contains('verif')) return 'verification_failed';
  return 'store_error';
}
