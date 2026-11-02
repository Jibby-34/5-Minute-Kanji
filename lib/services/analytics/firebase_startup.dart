import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart';

/// Starts Firebase once. A missing configuration file is not fatal: the app
/// keeps its current startup behavior and analytics calls become no-ops.
class FirebaseStartup {
  FirebaseStartup._();

  static Future<bool>? _starting;
  static bool _ready = false;
  static bool _handlersInstalled = false;

  static bool get isReady => _ready;

  /// Completes with false when Firebase cannot start. Never throws.
  static Future<bool> initialize() {
    final existing = _starting;
    if (existing != null) return existing;
    final run = _initialize();
    _starting = run;
    return run;
  }

  static Future<bool> _initialize() async {
    if (_ready || Firebase.apps.isNotEmpty) {
      _ready = Firebase.apps.isNotEmpty;
      return _ready;
    }
    try {
      // Native config (google-services.json / GoogleService-Info.plist) is
      // used when present. flutterfire configure can later pass
      // DefaultFirebaseOptions.currentPlatform here. Do not invent keys.
      await Firebase.initializeApp();
      _ready = true;
      return true;
    } catch (error) {
      debugPrint('Firebase did not start. Analytics and Crashlytics are off.');
      debugPrint('$error');
      _ready = false;
      return false;
    }
  }

  /// Records uncaught Flutter and async errors as fatal crashes.
  ///
  /// Caught study and purchase failures stay in their existing handlers and
  /// are not reported as crashes. Safe to call more than once.
  static void installCrashHandlers() {
    if (!_ready || _handlersInstalled) return;
    _handlersInstalled = true;
    final crashlytics = FirebaseCrashlytics.instance;
    FlutterError.onError = (details) {
      crashlytics.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        crashlytics
            .recordError(error, stack, fatal: true)
            .catchError((Object _) {}),
      );
      return true;
    };
  }
}

/// Forwards events to Firebase Analytics. Parameter checks happen earlier.
class FirebaseAnalyticsClient extends AnalyticsClient {
  FirebaseAnalyticsClient({FirebaseAnalytics? analytics})
    : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) {
    return _analytics.logEvent(
      name: name,
      parameters: parameters.isEmpty ? null : parameters,
    );
  }
}
