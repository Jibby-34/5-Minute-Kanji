import 'package:flutter/material.dart';

/// Navigator handle for events that arrive from outside the widget tree, such
/// as a tapped reminder.
class AppNavigator {
  const AppNavigator._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  /// Returns to the Home screen, where the day's workload and Start Review
  /// already live. No session is started automatically.
  static void openHome() {
    final navigator = key.currentState;
    if (navigator == null || !navigator.canPop()) return;
    navigator.popUntil((route) => route.isFirst);
  }
}
