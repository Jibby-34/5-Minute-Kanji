/// Monthly subscription as last reported by the store, or read back from cache.
enum MonthlySubscriptionState {
  none,
  active,
  gracePeriod,
  billingRetry,
  expired,
  refunded,
}

/// Pure full-access decision. Lifetime wins over every subscription state.
class CurriculumEntitlement {
  const CurriculumEntitlement({
    this.lifetime = false,
    this.subscription = MonthlySubscriptionState.none,
    this.subscriptionExpiresAt,
  });

  final bool lifetime;
  final MonthlySubscriptionState subscription;
  final DateTime? subscriptionExpiresAt;

  bool hasFullAccess(DateTime now) {
    if (lifetime) return true;
    return subscriptionGrantsAccess(now);
  }

  /// Active, grace, and billing-retry subscriptions unlock new kanji.
  ///
  /// An [MonthlySubscriptionState.active] record whose expiry has passed does
  /// not. That is the offline case: the cached date elapsed before the store
  /// could be asked again. Grace and billing retry stay open even when the
  /// paid period's date is already past.
  bool subscriptionGrantsAccess(DateTime now) {
    switch (subscription) {
      case MonthlySubscriptionState.active:
        final expiry = subscriptionExpiresAt;
        if (expiry == null) return true;
        return expiry.isAfter(now);
      case MonthlySubscriptionState.gracePeriod:
      case MonthlySubscriptionState.billingRetry:
        return true;
      case MonthlySubscriptionState.none:
      case MonthlySubscriptionState.expired:
      case MonthlySubscriptionState.refunded:
        return false;
    }
  }
}

/// Adds a Play billing period such as `P1M` onto [start].
///
/// Unknown periods fall back to 30 days so a missing product detail cannot
/// grant a permanent subscription.
DateTime addBillingPeriod(DateTime start, String period) {
  final match = RegExp(
    r'^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?$',
  ).firstMatch(period.trim());
  if (match == null) return start.add(const Duration(days: 30));
  final years = int.tryParse(match.group(1) ?? '') ?? 0;
  final months = int.tryParse(match.group(2) ?? '') ?? 0;
  final weeks = int.tryParse(match.group(3) ?? '') ?? 0;
  final days = int.tryParse(match.group(4) ?? '') ?? 0;
  if (years == 0 && months == 0 && weeks == 0 && days == 0) {
    return start.add(const Duration(days: 30));
  }
  final shifted = start.isUtc
      ? DateTime.utc(
          start.year + years,
          start.month + months,
          start.day,
          start.hour,
          start.minute,
          start.second,
          start.millisecond,
          start.microsecond,
        )
      : DateTime(
          start.year + years,
          start.month + months,
          start.day,
          start.hour,
          start.minute,
          start.second,
          start.millisecond,
          start.microsecond,
        );
  return shifted.add(Duration(days: weeks * 7 + days));
}

/// Play still returns a subscription during the paid period and grace period.
///
/// Call this only for a purchase Play listed as owned. A date in the past
/// means the paid month has ended and Play is still reporting the subscription,
/// which is the grace period. Account hold is not returned by Play's client
/// query; [MonthlySubscriptionState.billingRetry] is set when a caller already
/// knows that state.
({MonthlySubscriptionState state, DateTime? expiresAt}) androidMonthlyState({
  required DateTime purchaseTime,
  required DateTime now,
  String billingPeriod = 'P1M',
}) {
  final expiresAt = addBillingPeriod(purchaseTime, billingPeriod);
  if (now.isBefore(expiresAt)) {
    return (state: MonthlySubscriptionState.active, expiresAt: expiresAt);
  }
  return (state: MonthlySubscriptionState.gracePeriod, expiresAt: expiresAt);
}

/// StoreKit subscription transaction.
///
/// [fromCurrentEntitlements] is true for a restore of `Transaction.currentEntitlements`.
/// Apple keeps grace-period and billing-retry subscriptions in that set after
/// `expirationDate`. A past date from the full transaction history, which also
/// contains expired subscriptions, is treated as expired.
({MonthlySubscriptionState state, DateTime? expiresAt}) appleMonthlyState({
  required DateTime now,
  DateTime? expiresAt,
  DateTime? revocationDate,
  bool fromCurrentEntitlements = false,
}) {
  if (revocationDate != null) {
    return (state: MonthlySubscriptionState.refunded, expiresAt: expiresAt);
  }
  if (expiresAt == null || expiresAt.isAfter(now)) {
    return (state: MonthlySubscriptionState.active, expiresAt: expiresAt);
  }
  if (fromCurrentEntitlements) {
    return (state: MonthlySubscriptionState.billingRetry, expiresAt: expiresAt);
  }
  return (state: MonthlySubscriptionState.expired, expiresAt: expiresAt);
}
