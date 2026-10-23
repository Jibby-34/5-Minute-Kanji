import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../repositories/progress_repository.dart';
import 'curriculum_analytics.dart';
import 'curriculum_billing.dart';
import 'curriculum_entitlement.dart';
import 'curriculum_products.dart';
import 'curriculum_repository.dart';
import 'learned_kanji_backfill.dart';

enum CurriculumActivity { idle, purchasing, pending, restoring }

enum CurriculumNotice {
  none,
  unlocked,
  pending,
  failed,
  nothingToRestore,
  cancelled,
  cancelMonthly,
}

enum StoreReachability { unknown, available, unavailable }

/// Whether a new learn was allowed, and whether this call added the kanji.
class StudyRecordResult {
  const StudyRecordResult({
    required this.allowed,
    required this.newlyRecorded,
  });

  final bool allowed;
  final bool newlyRecorded;

  static const blocked = StudyRecordResult(
    allowed: false,
    newlyRecorded: false,
  );
}

/// Full-version entitlement and the 50-kanji trial.
///
/// Learning checks and purchase updates go through this object so widgets do
/// not talk to the store themselves. A purchase button does not set
/// [unlocked]; only a verified store update does.
class CurriculumAccess extends ChangeNotifier {
  CurriculumAccess({
    required this.progressRepository,
    required this.repository,
    required this.billing,
    this.analytics = const CurriculumAnalytics(),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final ProgressRepository progressRepository;
  final CurriculumRepository repository;
  final CurriculumBilling billing;
  final CurriculumAnalytics analytics;
  final DateTime Function() clock;

  final _AsyncLock _lock = _AsyncLock();
  Future<void>? _loading;
  StreamSubscription<List<CurriculumPurchaseUpdate>>? _updates;
  CurriculumRecord _record = const CurriculumRecord();
  CurriculumProduct? _lifetimeProduct;
  CurriculumProduct? _monthlyProduct;
  CurriculumActivity _activity = CurriculumActivity.idle;
  CurriculumNotice _notice = CurriculumNotice.none;
  String? _purchaseMessage;
  StoreReachability _store = StoreReachability.unknown;
  bool _productsFailed = false;
  bool _loaded = false;
  bool _disposed = false;
  bool _listening = false;
  int _entitlementEpoch = 0;

  bool get isLoaded => _loaded;

  /// Lifetime purchase. This stays true after a monthly subscription ends.
  bool get lifetimeOwned => _record.unlocked;

  CurriculumEntitlement get entitlement => CurriculumEntitlement(
    lifetime: _record.unlocked,
    subscription: _record.subscription,
    subscriptionExpiresAt: _record.subscriptionExpiresAt,
  );

  /// Lifetime, or a monthly subscription that is still active, in grace, or
  /// in billing retry. An expired or refunded subscription does not count.
  bool get unlocked => entitlement.hasFullAccess(clock());

  bool get subscriptionActive => entitlement.subscriptionGrantsAccess(clock());

  /// Lifetime was bought while the monthly subscription still grants access.
  bool get promptCancelMonthly => lifetimeOwned && subscriptionActive;

  bool get storeUnavailable => _store == StoreReachability.unavailable;

  bool get productsFailedToLoad => _productsFailed;

  int get studiedCount => _record.studiedIds.length;

  Set<String> get studiedIds => Set.unmodifiable(_record.studiedIds);

  bool get canLearnNewKanji =>
      _loaded && (unlocked || studiedCount < freeKanjiLimit);

  bool get trialLimitReached =>
      _loaded && !unlocked && studiedCount >= freeKanjiLimit;

  bool canIntroduce(String cardId) {
    if (!_loaded || cardId.isEmpty) return false;
    if (unlocked || _record.studiedIds.contains(cardId)) return true;
    return studiedCount < freeKanjiLimit;
  }

  String get trialProgressLabel =>
      '$studiedCount / $freeKanjiLimit free kanji learned';

  String? get localizedPrice => _priceOf(_lifetimeProduct);

  String? get monthlyPrice => _priceOf(_monthlyProduct);

  String? _priceOf(CurriculumProduct? product) {
    final price = product?.price.trim();
    if (price == null || price.isEmpty) return null;
    return price;
  }

  bool get priceLoaded => localizedPrice != null;

  /// Dialog action. Includes the store price when the product has loaded.
  String get purchaseButtonLabel {
    final price = localizedPrice;
    if (price == null) return 'Unlock full version';
    return 'Unlock full version · $price';
  }

  String get monthlyButtonLabel {
    final price = monthlyPrice;
    if (price == null) return 'Subscribe monthly';
    return 'Subscribe monthly · $price';
  }

  String get monthlyDisclosure {
    final price = monthlyPrice;
    final cost = price == null
        ? 'The monthly price will appear when the store responds.'
        : '$price per month.';
    return '$cost Renews automatically until you cancel. '
        'Cancel anytime in your App Store or Google Play account settings.';
  }

  CurriculumActivity get activity => _activity;

  CurriculumNotice get notice => _notice;

  String? get purchaseMessage => _purchaseMessage;

  bool get purchaseInProgress =>
      _activity == CurriculumActivity.purchasing ||
      _activity == CurriculumActivity.pending ||
      _activity == CurriculumActivity.restoring;

  Future<void> load() => ensureLoaded();

  /// Re-reads the cached expiry, then asks the store when it is reachable.
  ///
  /// Called on launch, when the app returns to the foreground, and after a
  /// purchase or restore.
  Future<void> refresh() async {
    await ensureLoaded();
    if (_disposed) return;
    _notify();
    await _refreshStore();
  }

  Future<void> ensureLoaded() {
    final current = _loading;
    if (current != null) return current;
    final run = _load();
    _loading = run;
    return run.catchError((Object error, StackTrace stack) {
      if (identical(_loading, run)) _loading = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  /// Records [cardId] when it may be learned. Safe to call twice: the second
  /// call does not consume another trial credit. Concurrent calls share one
  /// lock, so two introductions cannot both pass the 50-kanji cap.
  Future<StudyRecordResult> tryRecordStudy(String cardId) async {
    if (cardId.isEmpty) return StudyRecordResult.blocked;
    await ensureLoaded();
    return _lock.run(() async {
      if (_record.studiedIds.contains(cardId)) {
        return const StudyRecordResult(allowed: true, newlyRecorded: false);
      }
      if (!unlocked && _record.studiedIds.length >= freeKanjiLimit) {
        return StudyRecordResult.blocked;
      }
      final next = _record.copyWith(
        studiedIds: {..._record.studiedIds, cardId},
      );
      await repository.write(next);
      _record = next;
      _notify();
      return const StudyRecordResult(allowed: true, newlyRecorded: true);
    });
  }

  /// Drops a credit that was recorded but whose schedule never saved.
  Future<void> forgetStudy(String cardId) async {
    if (cardId.isEmpty) return;
    await ensureLoaded();
    await _lock.run(() async {
      if (!_record.studiedIds.contains(cardId)) return;
      final next = _record.copyWith(
        studiedIds: {..._record.studiedIds}..remove(cardId),
      );
      await repository.write(next);
      _record = next;
      _notify();
    });
  }

  /// Opens the native purchase sheet. [unlocked] stays false until the store
  /// reports a verified purchase.
  Future<void> buy() => _buy(fullCurriculumUnlock);

  Future<void> buyMonthly() => _buy(fullCurriculumMonthly);

  Future<void> _buy(String productId) async {
    if (_disposed || purchaseInProgress) return;
    if (productId == fullCurriculumUnlock && lifetimeOwned) return;
    if (productId == fullCurriculumMonthly &&
        (lifetimeOwned || subscriptionActive)) {
      return;
    }
    await ensureLoaded();
    analytics.purchaseStarted(productId);
    _activity = CurriculumActivity.purchasing;
    _notice = CurriculumNotice.none;
    _purchaseMessage = null;
    _notify();
    try {
      final product = await _productOrLoad(productId);
      if (product == null) {
        _fail(
          _store == StoreReachability.unavailable
              ? 'The store is unavailable right now.'
              : 'The store products could not be loaded.',
        );
        return;
      }
      final started = await billing.startPurchase(product);
      if (!started) {
        _fail('The store could not start the purchase.');
        return;
      }
      // The store sheet owns the next step. Leave the app usable if that
      // result has not arrived yet; the purchase stream still grants,
      // cancels, or fails the entitlement.
      if (_activity == CurriculumActivity.purchasing) {
        _activity = CurriculumActivity.idle;
        _notify();
      }
    } catch (_) {
      _fail('The store could not start the purchase.');
    }
  }

  Future<void> restore() async {
    if (_disposed || purchaseInProgress) return;
    await ensureLoaded();
    analytics.restoreTapped();
    _activity = CurriculumActivity.restoring;
    _notice = CurriculumNotice.none;
    _purchaseMessage = null;
    _notify();
    final epoch = _entitlementEpoch;
    try {
      await billing.restorePurchases();
      await _applyEntitlementQuery();
    } catch (_) {
      if (_disposed) return;
      _activity = CurriculumActivity.idle;
      _notice = CurriculumNotice.failed;
      _purchaseMessage = 'Could not restore purchases.';
      _notify();
      return;
    }
    if (_disposed) return;
    if (_activity == CurriculumActivity.restoring) {
      _activity = CurriculumActivity.idle;
    }
    if (!unlocked && epoch == _entitlementEpoch) {
      _notice = CurriculumNotice.nothingToRestore;
      _purchaseMessage = 'No purchases to restore.';
    }
    _notify();
  }

  Future<void> _load() async {
    _listen();
    await _lock.run(() async {
      var record = await repository.read();
      if (!record.backfillCompleted) {
        final schedules = await progressRepository.getSchedules();
        record = record.copyWith(
          studiedIds: LearnedKanjiBackfill.idsFrom(schedules.values),
          backfillCompleted: true,
        );
        await repository.write(record);
      }
      _record = record;
      _loaded = true;
    });
    _notify();
    unawaited(_refreshStore());
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    _updates = billing.purchaseUpdates.listen(
      _onPurchaseUpdates,
      onError: (_) {
        if (_activity == CurriculumActivity.purchasing ||
            _activity == CurriculumActivity.restoring) {
          _fail('The store could not finish the purchase.');
        }
      },
    );
  }

  Future<void> _refreshStore() async {
    if (_disposed) return;
    try {
      final available = await billing.isAvailable();
      if (_disposed) return;
      if (!available) {
        _store = StoreReachability.unavailable;
        _notify();
        return;
      }
      _store = StoreReachability.available;
      final catalog = await billing.loadCatalog();
      if (_disposed) return;
      _lifetimeProduct = catalog.lifetime;
      _monthlyProduct = catalog.monthly;
      _productsFailed = catalog.isEmpty;
      _notify();
      await _applyEntitlementQuery();
    } catch (_) {
      // Keep the cached entitlement and leave study usable.
      if (_disposed) return;
      _store = StoreReachability.unavailable;
      _notify();
    }
  }

  Future<void> _applyEntitlementQuery() async {
    final epoch = _entitlementEpoch;
    final snapshot = await billing.queryStoreEntitlement();
    if (_disposed || epoch != _entitlementEpoch) return;
    var next = _record;
    var changed = false;
    switch (snapshot.lifetime) {
      case EntitlementQueryResult.owned:
        if (!next.unlocked) {
          next = next.copyWith(unlocked: true);
          changed = true;
        }
      case EntitlementQueryResult.notOwned:
        if (next.unlocked) {
          next = next.copyWith(unlocked: false);
          changed = true;
        }
      case EntitlementQueryResult.unavailable:
        break;
    }
    if (snapshot.subscriptionKnown) {
      final sameExpiry = _sameInstant(
        next.subscriptionExpiresAt,
        snapshot.subscriptionExpiresAt,
      );
      if (next.subscription != snapshot.subscription || !sameExpiry) {
        next = next.copyWith(
          subscription: snapshot.subscription,
          subscriptionExpiresAt: snapshot.subscriptionExpiresAt,
          clearSubscriptionExpiry: snapshot.subscriptionExpiresAt == null,
        );
        changed = true;
      }
    }
    if (!changed) {
      _notify();
      return;
    }
    await _persistEntitlement(
      epoch: epoch,
      lifetime: next.unlocked,
      subscription: snapshot.subscriptionKnown ? next.subscription : null,
      subscriptionExpiresAt: snapshot.subscriptionKnown
          ? next.subscriptionExpiresAt
          : null,
      clearSubscriptionExpiry:
          snapshot.subscriptionKnown && next.subscriptionExpiresAt == null,
      touchSubscription: snapshot.subscriptionKnown,
    );
  }

  Future<void> _onPurchaseUpdates(List<CurriculumPurchaseUpdate> updates) async {
    for (final update in updates) {
      if (!update.isFullCurriculum && !update.isMonthly) continue;
      if (update.grantsEntitlement) {
        await _grantLifetime(update);
        continue;
      }
      if (update.isMonthly && _isSubscriptionLapse(update)) {
        await _applySubscriptionUpdate(update, grants: false);
        continue;
      }
      if (update.grantsSubscription) {
        await _applySubscriptionUpdate(update, grants: true);
        continue;
      }
      if (update.status == CurriculumPurchaseStatus.pending) {
        _activity = CurriculumActivity.pending;
        _notice = CurriculumNotice.pending;
        _purchaseMessage = 'Purchase pending approval.';
        _notify();
        continue;
      }
      if (update.isCancellation) {
        analytics.purchaseCancelled(update.productId);
        _activity = CurriculumActivity.idle;
        _notice = CurriculumNotice.cancelled;
        _purchaseMessage = 'Purchase cancelled.';
        _notify();
        await _completeQuietly(update);
        continue;
      }
      if (update.status == CurriculumPurchaseStatus.error) {
        _fail(_failureMessage(update));
        await _completeQuietly(update);
        continue;
      }
      if (update.status == CurriculumPurchaseStatus.purchased ||
          update.status == CurriculumPurchaseStatus.restored) {
        _fail('Purchase could not be verified.');
      }
    }
  }

  bool _isSubscriptionLapse(CurriculumPurchaseUpdate update) {
    if (update.status != CurriculumPurchaseStatus.purchased &&
        update.status != CurriculumPurchaseStatus.restored) {
      return false;
    }
    final state = update.subscriptionState;
    return state == MonthlySubscriptionState.expired ||
        state == MonthlySubscriptionState.refunded;
  }

  Future<void> _grantLifetime(CurriculumPurchaseUpdate update) async {
    final epoch = ++_entitlementEpoch;
    await _persistEntitlement(epoch: epoch, lifetime: true);
    if (_disposed) return;
    analytics.purchaseSucceeded(update.productId);
    _activity = CurriculumActivity.idle;
    if (entitlement.subscriptionGrantsAccess(clock())) {
      _notice = CurriculumNotice.cancelMonthly;
      _purchaseMessage =
          'Lifetime is unlocked. Cancel the monthly subscription in your '
          'store account settings so you are not billed again. It can\'t be '
          'cancelled from inside the app.';
    } else {
      _notice = CurriculumNotice.unlocked;
      _purchaseMessage = null;
    }
    _notify();
    try {
      await billing.complete(update);
    } catch (_) {}
  }

  Future<void> _applySubscriptionUpdate(
    CurriculumPurchaseUpdate update, {
    required bool grants,
  }) async {
    final epoch = ++_entitlementEpoch;
    final state = update.subscriptionState ??
        (grants
            ? MonthlySubscriptionState.active
            : MonthlySubscriptionState.expired);
    await _persistEntitlement(
      epoch: epoch,
      subscription: state,
      subscriptionExpiresAt: update.subscriptionExpiresAt,
      clearSubscriptionExpiry: update.subscriptionExpiresAt == null,
      touchSubscription: true,
    );
    if (_disposed) return;
    _activity = CurriculumActivity.idle;
    if (grants && entitlement.subscriptionGrantsAccess(clock())) {
      analytics.purchaseSucceeded(update.productId);
      _notice = CurriculumNotice.unlocked;
      _purchaseMessage = null;
    } else {
      _notice = CurriculumNotice.none;
      _purchaseMessage = null;
    }
    _notify();
    try {
      await billing.complete(update);
    } catch (_) {}
  }

  /// Writes entitlement fields onto the current record so a study recorded
  /// while the store query was in flight is not lost.
  Future<void> _persistEntitlement({
    required int epoch,
    bool? lifetime,
    MonthlySubscriptionState? subscription,
    DateTime? subscriptionExpiresAt,
    bool clearSubscriptionExpiry = false,
    bool touchSubscription = false,
  }) async {
    await _lock.run(() async {
      if (epoch != _entitlementEpoch) return;
      final next = _record.copyWith(
        unlocked: lifetime,
        subscription: subscription,
        subscriptionExpiresAt: subscriptionExpiresAt,
        clearSubscriptionExpiry: clearSubscriptionExpiry,
      );
      final sameLifetime = _record.unlocked == next.unlocked;
      final sameSubscription =
          !touchSubscription ||
          (_record.subscription == next.subscription &&
              _sameInstant(
                _record.subscriptionExpiresAt,
                next.subscriptionExpiresAt,
              ));
      if (sameLifetime && sameSubscription) return;
      await repository.write(next);
      _record = next;
    });
    _notify();
  }

  Future<CurriculumProduct?> _productOrLoad(String productId) async {
    final existing = productId == fullCurriculumMonthly
        ? _monthlyProduct
        : _lifetimeProduct;
    if (existing != null) return existing;
    try {
      final catalog = await billing.loadCatalog();
      _lifetimeProduct = catalog.lifetime ?? _lifetimeProduct;
      _monthlyProduct = catalog.monthly ?? _monthlyProduct;
      _productsFailed = catalog.isEmpty;
      _notify();
      return productId == fullCurriculumMonthly
          ? _monthlyProduct
          : _lifetimeProduct;
    } catch (_) {
      _store = StoreReachability.unavailable;
      return null;
    }
  }

  void _fail(String message) {
    if (_disposed) return;
    _activity = CurriculumActivity.idle;
    _notice = CurriculumNotice.failed;
    _purchaseMessage = message;
    _notify();
  }

  String _failureMessage(CurriculumPurchaseUpdate update) {
    final message = update.errorMessage?.trim();
    if (message == null || message.isEmpty) {
      return 'The purchase could not be completed.';
    }
    return message;
  }

  Future<void> _completeQuietly(CurriculumPurchaseUpdate update) async {
    if (!update.pendingComplete) return;
    try {
      await billing.complete(update);
    } catch (_) {}
  }

  bool _sameInstant(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == right;
    return left.toUtc() == right.toUtc();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    super.dispose();
  }
}

class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final gate = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return gate.then((_) => action()).whenComplete(done.complete);
  }
}
