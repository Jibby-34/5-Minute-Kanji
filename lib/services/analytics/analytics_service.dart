import 'dart:async';

/// Sends one analytics event. Implementations must not be required for study
/// to work. [AnalyticsService] catches failures from this callback.
abstract class AnalyticsClient {
  const AnalyticsClient();

  Future<void> logEvent(String name, Map<String, Object> parameters);
}

/// Drops every event. Used before Firebase is configured and in tests that
/// do not assert on analytics.
class NoopAnalyticsClient extends AnalyticsClient {
  const NoopAnalyticsClient();

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {}
}

/// Product analytics for growth, study, and purchases.
///
/// Methods return immediately. Sending never blocks a study session, and a
/// failure inside the client is ignored. Construct one instance for the
/// process and pass it through the widget tree. Firebase lifecycle events
/// such as `first_open`, `session_start`, and `user_engagement` are left to
/// the SDK.
///
/// Boolean parameters are sent as 1 or 0 because Firebase Analytics event
/// parameters are strings or numbers.
class AnalyticsService {
  AnalyticsService({
    AnalyticsClient? client,
    List<String> reportedTransactionIds = const [],
    this.onReportedTransactionIdsChanged,
  }) : _client = client ?? const NoopAnalyticsClient(),
       _reportedTransactionIds = List<String>.of(reportedTransactionIds);

  /// SharedPreferences key for purchase ids already sent. The ids are store
  /// transaction ids, not user identifiers.
  static const reportedTransactionIdsKey = 'analytics_reported_transactions_v1';

  static const _reportedTransactionLimit = 40;
  static const _valueLimit = 100;

  final AnalyticsClient _client;
  final List<String> _reportedTransactionIds;
  final void Function(List<String> ids)? onReportedTransactionIdsChanged;

  /// True the first time [key] is seen. Later calls are duplicates.
  ///
  /// An empty key is not claimed, so the caller skips the event rather than
  /// logging an unidentifiable purchase more than once.
  bool claimTransaction(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty || normalized.length > 180) return false;
    if (_reportedTransactionIds.contains(normalized)) return false;
    _reportedTransactionIds.add(normalized);
    while (_reportedTransactionIds.length > _reportedTransactionLimit) {
      _reportedTransactionIds.removeAt(0);
    }
    _persistTransactions();
    return true;
  }

  void _persistTransactions() {
    final persist = onReportedTransactionIdsChanged;
    if (persist == null) return;
    try {
      persist(List<String>.unmodifiable(_reportedTransactionIds));
    } catch (_) {}
  }

  void onboardingStarted() {
    _emit('onboarding_started', const {});
  }

  void onboardingCompleted({
    int? dailyGoalMinutes,
    Object? startingLevel,
    String? startingMethod,
  }) {
    _emit('onboarding_completed', {
      'daily_goal_minutes': dailyGoalMinutes,
      'starting_level': startingLevel,
      'starting_method': startingMethod,
    });
  }

  void placementTestStarted() {
    _emit('placement_test_started', const {});
  }

  void placementTestCompleted({
    required int questionsAnswered,
    int? estimatedLevel,
  }) {
    _emit('placement_test_completed', {
      'questions_answered': questionsAnswered,
      'estimated_level': estimatedLevel,
    });
  }

  void studySessionStarted({required String sessionType, int? availableCards}) {
    _emit('study_session_started', {
      'session_type': sessionType,
      'available_cards': availableCards,
    });
  }

  void kanjiReviewed({
    required String result,
    required bool isNew,
    required String reviewCategory,
  }) {
    _emit('kanji_reviewed', {
      'result': result,
      'is_new': isNew,
      'review_category': reviewCategory,
    });
  }

  void studySessionCompleted({
    required int durationSeconds,
    required int cardsReviewed,
    required int newCardsLearned,
    required bool goalCompleted,
    required String sessionType,
  }) {
    _emit('study_session_completed', {
      'duration_seconds': durationSeconds,
      'cards_reviewed': cardsReviewed,
      'new_cards_learned': newCardsLearned,
      'goal_completed': goalCompleted,
      'session_type': sessionType,
    });
  }

  void studySessionAbandoned({
    required int durationSeconds,
    required int cardsReviewed,
    required String sessionType,
  }) {
    _emit('study_session_abandoned', {
      'duration_seconds': durationSeconds,
      'cards_reviewed': cardsReviewed,
      'session_type': sessionType,
    });
  }

  void reinforcementDayStarted({
    required String dayType,
    String? triggerCategory,
  }) {
    _emit('reinforcement_day_started', {
      'day_type': dayType,
      'trigger_category': triggerCategory,
    });
  }

  void paywallViewed({required String placement}) {
    _emit('paywall_viewed', {'placement': placement});
  }

  void purchaseStarted({
    required String productId,
    required String purchaseType,
  }) {
    _emit('purchase_started', {
      'product_id': productId,
      'purchase_type': purchaseType,
    });
  }

  void purchaseCompleted({
    required String productId,
    required String purchaseType,
  }) {
    _emit('purchase_completed', {
      'product_id': productId,
      'purchase_type': purchaseType,
    });
  }

  void purchaseFailed({
    required String productId,
    required String purchaseType,
    required String errorCategory,
  }) {
    _emit('purchase_failed', {
      'product_id': productId,
      'purchase_type': purchaseType,
      'error_category': errorCategory,
    });
  }

  void purchaseRestored({
    required String productId,
    required String purchaseType,
  }) {
    _emit('purchase_restored', {
      'product_id': productId,
      'purchase_type': purchaseType,
    });
  }

  void dailyGoalChanged({required int dailyGoalMinutes}) {
    _emit('daily_goal_changed', {'daily_goal_minutes': dailyGoalMinutes});
  }

  void reminderSettingsChanged({
    required bool enabled,
    required int reminderHour,
    required int reminderMinute,
  }) {
    _emit('reminder_settings_changed', {
      'enabled': enabled,
      'reminder_hour': reminderHour,
      'reminder_minute': reminderMinute,
    });
  }

  void _emit(String name, Map<String, Object?> parameters) {
    if (!_validEventName(name)) return;
    final sanitized = sanitizeAnalyticsParameters(parameters);
    unawaited(_send(name, sanitized));
  }

  Future<void> _send(String name, Map<String, Object> parameters) async {
    try {
      await _client.logEvent(name, parameters);
    } catch (_) {}
  }
}

/// Drops nulls, non-finite numbers, and values Firebase Analytics will reject.
/// Booleans become 1 or 0. Strings are trimmed to 100 characters.
Map<String, Object> sanitizeAnalyticsParameters(
  Map<String, Object?> parameters,
) {
  final sanitized = <String, Object>{};
  for (final entry in parameters.entries) {
    final name = _validParameterName(entry.key);
    final value = _validParameterValue(entry.value);
    if (name == null || value == null) continue;
    sanitized[name] = value;
  }
  return sanitized;
}

bool _validEventName(String name) {
  return name.length <= 40 && RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(name);
}

String? _validParameterName(String name) {
  if (name.length > 40) return null;
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(name)) return null;
  return name;
}

Object? _validParameterValue(Object? value) {
  if (value == null) return null;
  if (value is bool) return value ? 1 : 0;
  if (value is int) return value < 0 ? 0 : value;
  if (value is double) {
    if (!value.isFinite || value < 0) return null;
    return value;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= AnalyticsService._valueLimit) return trimmed;
    return trimmed.substring(0, AnalyticsService._valueLimit);
  }
  return null;
}
