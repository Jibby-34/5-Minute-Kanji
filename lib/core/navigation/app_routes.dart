import 'package:flutter/material.dart';

/// Platform-aware session routes: iOS presents as a fullscreen sheet.
class AppRoutes {
  static Route<T> session<T extends Object?>(
    BuildContext context,
    Widget page,
  ) {
    final platform = Theme.of(context).platform;
    final cupertino =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    return MaterialPageRoute<T>(
      builder: (_) => page,
      fullscreenDialog: cupertino,
    );
  }
}
