import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'curriculum_billing.dart';
import 'curriculum_entitlement.dart';
import 'curriculum_products.dart';

/// App Store and Play Billing adapter for the lifetime unlock and the monthly
/// subscription.
///
/// Purchases are acknowledged only after the app has accepted them. Android
/// refunds a purchase that is not acknowledged within three days. iOS leaves
/// an unfinished transaction in the queue until [complete] runs.
///
/// This class does not run a server. See docs/full-version-purchase.md.
/// Empty verification data is rejected so a tap, by itself, cannot unlock
/// the curriculum.
class StoreCurriculumBilling implements CurriculumBilling {
  StoreCurriculumBilling({InAppPurchase? inAppPurchase, DateTime Function()? clock})
    : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance,
      _clock = clock ?? DateTime.now;

  final InAppPurchase _inAppPurchase;
  final DateTime Function() _clock;
  final Set<String> _completedPurchaseIds = {};

  @override
  Future<bool> isAvailable() => _inAppPurchase.isAvailable();

  @override
  Future<CurriculumProduct?> loadProduct() async {
    final catalog = await loadCatalog();
    return catalog.lifetime;
  }

  @override
  Future<CurriculumCatalog> loadCatalog() async {
    final response = await _inAppPurchase.queryProductDetails({
      fullCurriculumUnlock,
      fullCurriculumMonthly,
    });
    if (response.error != null && response.productDetails.isEmpty) {
      return const CurriculumCatalog();
    }
    CurriculumProduct? lifetime;
    for (final details in response.productDetails) {
      if (details.id == fullCurriculumUnlock) {
        lifetime = CurriculumProduct(
          id: details.id,
          price: details.price,
          raw: details,
        );
        break;
      }
    }
    final monthly = _monthlyProduct(response.productDetails);
    return CurriculumCatalog(lifetime: lifetime, monthly: monthly);
  }

  @override
  Future<bool> startPurchase(CurriculumProduct product) async {
    final details = product.raw;
    if (details is! ProductDetails) return false;
    if (details.id == fullCurriculumUnlock) {
      return _inAppPurchase.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
    }
    if (details.id != fullCurriculumMonthly) return false;
    if (details is GooglePlayProductDetails) {
      return _inAppPurchase.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: details,
          offerToken: details.offerToken,
        ),
      );
    }
    return _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
  }

  @override
  Future<void> restorePurchases() => _inAppPurchase.restorePurchases();

  @override
  Future<EntitlementQueryResult> queryEntitlement() async {
    final snapshot = await queryStoreEntitlement();
    return snapshot.lifetime;
  }

  @override
  Future<StoreEntitlementSnapshot> queryStoreEntitlement() async {
    if (kIsWeb) {
      return const StoreEntitlementSnapshot(
        lifetime: EntitlementQueryResult.unavailable,
      );
    }
    if (Platform.isAndroid) return _queryAndroid();
    if (Platform.isIOS || Platform.isMacOS) return _queryApple();
    return const StoreEntitlementSnapshot(
      lifetime: EntitlementQueryResult.unavailable,
    );
  }

  @override
  Stream<List<CurriculumPurchaseUpdate>> get purchaseUpdates {
    return _inAppPurchase.purchaseStream.map(
      (purchases) => purchases.map(_map).toList(),
    );
  }

  @override
  Future<void> complete(CurriculumPurchaseUpdate update) async {
    final raw = update.raw;
    if (raw is! PurchaseDetails) return;
    final id = update.purchaseId;
    if (id != null && id.isNotEmpty && !_completedPurchaseIds.add(id)) return;
    await _inAppPurchase.completePurchase(raw);
  }

  Future<StoreEntitlementSnapshot> _queryAndroid() async {
    if (!await isAvailable()) {
      return const StoreEntitlementSnapshot(
        lifetime: EntitlementQueryResult.unavailable,
      );
    }
    final android = _inAppPurchase
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await android.queryPastPurchases();
    if (response.error != null) {
      return const StoreEntitlementSnapshot(
        lifetime: EntitlementQueryResult.unavailable,
      );
    }

    var lifetimePending = false;
    var lifetimeOwned = false;
    var monthlyPending = false;
    MonthlySubscriptionState? monthly;
    DateTime? monthlyExpiry;
    for (final purchase in response.pastPurchases) {
      final update = _map(purchase);
      if (update.isFullCurriculum) {
        if (update.status == CurriculumPurchaseStatus.pending) {
          lifetimePending = true;
          continue;
        }
        if (!update.grantsEntitlement) continue;
        lifetimeOwned = true;
        if (update.pendingComplete) await complete(update);
        continue;
      }
      if (!update.isMonthly) continue;
      if (update.status == CurriculumPurchaseStatus.pending) {
        monthlyPending = true;
        continue;
      }
      if (update.subscriptionState == null) continue;
      monthly = _preferMonthly(monthly, update.subscriptionState!);
      monthlyExpiry = update.subscriptionExpiresAt ?? monthlyExpiry;
      if (update.grantsSubscription && update.pendingComplete) {
        await complete(update);
      }
    }

    final lifetime = lifetimeOwned
        ? EntitlementQueryResult.owned
        : lifetimePending
        ? EntitlementQueryResult.unavailable
        : EntitlementQueryResult.notOwned;
    if (monthlyPending && monthly == null) {
      return StoreEntitlementSnapshot(lifetime: lifetime);
    }
    return StoreEntitlementSnapshot(
      lifetime: lifetime,
      subscriptionKnown: true,
      subscription: monthly ?? MonthlySubscriptionState.none,
      subscriptionExpiresAt: monthlyExpiry,
    );
  }

  /// StoreKit 2 `Transaction.all` does not prompt for an Apple ID.
  ///
  /// Lifetime is cleared only when a revoked transaction is the evidence.
  /// Missing the lifetime product leaves the cache alone, matching the
  /// previous iOS behavior.
  Future<StoreEntitlementSnapshot> _queryApple() async {
    try {
      final transactions = await SK2Transaction.transactions();
      final now = _clock();
      var sawLifetime = false;
      var lifetimeActive = false;
      SK2Transaction? latestMonthly;
      DateTime? latestExpiry;
      for (final transaction in transactions) {
        if (transaction.productId == fullCurriculumUnlock) {
          sawLifetime = true;
          if (revocationDate(transaction.jsonRepresentation) == null) {
            lifetimeActive = true;
          }
          continue;
        }
        if (transaction.productId != fullCurriculumMonthly) continue;
        final expiry = storeDate(transaction.expirationDate);
        if (latestMonthly == null ||
            (expiry != null &&
                (latestExpiry == null || expiry.isAfter(latestExpiry)))) {
          latestMonthly = transaction;
          latestExpiry = expiry;
        }
      }
      final lifetime = !sawLifetime
          ? EntitlementQueryResult.unavailable
          : lifetimeActive
          ? EntitlementQueryResult.owned
          : EntitlementQueryResult.notOwned;
      if (latestMonthly == null) {
        return StoreEntitlementSnapshot(
          lifetime: lifetime,
          subscriptionKnown: true,
          subscription: MonthlySubscriptionState.none,
        );
      }
      final decision = appleMonthlyState(
        now: now,
        expiresAt: latestExpiry,
        revocationDate: revocationDate(latestMonthly.jsonRepresentation),
      );
      return StoreEntitlementSnapshot(
        lifetime: lifetime,
        subscriptionKnown: true,
        subscription: decision.state,
        subscriptionExpiresAt: decision.expiresAt,
      );
    } catch (_) {
      return const StoreEntitlementSnapshot(
        lifetime: EntitlementQueryResult.unavailable,
      );
    }
  }

  CurriculumPurchaseUpdate _map(PurchaseDetails purchase) {
    final error = purchase.error;
    final server = purchase.verificationData.serverVerificationData.trim();
    final local = purchase.verificationData.localVerificationData.trim();
    final verification = server.isNotEmpty ? server : local;
    MonthlySubscriptionState? subscriptionState;
    DateTime? subscriptionExpiresAt;
    if (purchase.productID == fullCurriculumMonthly) {
      final decision = _monthlyDecision(purchase, local);
      subscriptionState = decision?.state;
      subscriptionExpiresAt = decision?.expiresAt;
    }
    return CurriculumPurchaseUpdate(
      productId: purchase.productID,
      purchaseId: purchase.purchaseID,
      status: switch (purchase.status) {
        PurchaseStatus.pending => CurriculumPurchaseStatus.pending,
        PurchaseStatus.purchased => CurriculumPurchaseStatus.purchased,
        PurchaseStatus.restored => CurriculumPurchaseStatus.restored,
        PurchaseStatus.canceled => CurriculumPurchaseStatus.canceled,
        PurchaseStatus.error => CurriculumPurchaseStatus.error,
      },
      pendingComplete: purchase.pendingCompletePurchase,
      verificationData: verification,
      errorCode: error?.code,
      errorMessage: error?.message,
      raw: purchase,
      subscriptionState: subscriptionState,
      subscriptionExpiresAt: subscriptionExpiresAt,
    );
  }

  ({MonthlySubscriptionState state, DateTime? expiresAt})? _monthlyDecision(
    PurchaseDetails purchase,
    String localVerification,
  ) {
    if (purchase.status == PurchaseStatus.pending) return null;
    if (purchase is GooglePlayPurchaseDetails) {
      final bought = purchase.billingClientPurchase;
      if (bought.purchaseState != PurchaseStateWrapper.purchased) return null;
      return androidMonthlyState(
        purchaseTime: DateTime.fromMillisecondsSinceEpoch(bought.purchaseTime),
        now: _clock(),
      );
    }
    if (purchase is SK2PurchaseDetails) {
      return appleMonthlyState(
        now: _clock(),
        expiresAt: storeDate(purchase.expirationDate),
        revocationDate: revocationDate(localVerification),
        fromCurrentEntitlements: purchase.status == PurchaseStatus.restored,
      );
    }
    return null;
  }

  CurriculumProduct? _monthlyProduct(List<ProductDetails> products) {
    final matches = products
        .where((details) => details.id == fullCurriculumMonthly)
        .toList();
    if (matches.isEmpty) return null;
    GooglePlayProductDetails? monthlyPlan;
    for (final details in matches) {
      if (details is! GooglePlayProductDetails) {
        return CurriculumProduct(
          id: details.id,
          price: details.price,
          raw: details,
          billingPeriod: 'P1M',
        );
      }
      final offer = _offer(details);
      if (offer == null || offer.offerId != null) continue;
      final period = _recurringPeriod(offer);
      final isMonthly = offer.basePlanId == monthlyBasePlanId || period == 'P1M';
      if (!isMonthly) continue;
      monthlyPlan = details;
      if (offer.basePlanId == monthlyBasePlanId) break;
    }
    final chosen = monthlyPlan ?? matches.whereType<GooglePlayProductDetails>().firstOrNull;
    if (chosen == null) return null;
    final offer = _offer(chosen);
    final period = offer == null ? 'P1M' : _recurringPeriod(offer);
    return CurriculumProduct(
      id: chosen.id,
      price: _recurringPrice(chosen) ?? chosen.price,
      raw: chosen,
      billingPeriod: period,
    );
  }

  SubscriptionOfferDetailsWrapper? _offer(GooglePlayProductDetails details) {
    final index = details.subscriptionIndex;
    final offers = details.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null || index >= offers.length) return null;
    return offers[index];
  }

  String _recurringPeriod(SubscriptionOfferDetailsWrapper offer) {
    for (final phase in offer.pricingPhases.reversed) {
      if (phase.recurrenceMode == RecurrenceMode.infiniteRecurring) {
        return phase.billingPeriod;
      }
    }
    if (offer.pricingPhases.isEmpty) return 'P1M';
    return offer.pricingPhases.last.billingPeriod;
  }

  String? _recurringPrice(GooglePlayProductDetails details) {
    final offer = _offer(details);
    if (offer == null) return null;
    for (final phase in offer.pricingPhases.reversed) {
      if (phase.recurrenceMode == RecurrenceMode.infiniteRecurring) {
        return phase.formattedPrice;
      }
    }
    return null;
  }
}

MonthlySubscriptionState _preferMonthly(
  MonthlySubscriptionState? current,
  MonthlySubscriptionState next,
) {
  if (current == null) return next;
  if (_monthlyRank(next) > _monthlyRank(current)) return next;
  return current;
}

int _monthlyRank(MonthlySubscriptionState state) {
  return switch (state) {
    MonthlySubscriptionState.active => 5,
    MonthlySubscriptionState.gracePeriod => 4,
    MonthlySubscriptionState.billingRetry => 3,
    MonthlySubscriptionState.expired => 1,
    MonthlySubscriptionState.refunded => 1,
    MonthlySubscriptionState.none => 0,
  };
}

/// StoreKit's `expirationDate` is milliseconds since epoch, as a string.
DateTime? storeDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parsed = num.tryParse(raw);
  if (parsed != null) return _fromStoreNumber(parsed);
  return DateTime.tryParse(raw);
}

DateTime? revocationDate(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    return _storeValue(decoded['revocationDate']);
  } catch (_) {
    return null;
  }
}

DateTime? _storeValue(Object? value) {
  if (value == null) return null;
  if (value is num) return _fromStoreNumber(value);
  if (value is String) return storeDate(value);
  return null;
}

DateTime _fromStoreNumber(num value) {
  final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds.round(), isUtc: true);
}
