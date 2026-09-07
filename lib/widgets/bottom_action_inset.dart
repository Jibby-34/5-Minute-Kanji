import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Thumb-zone action bar sitting above the home indicator.
class BottomActionInset extends StatelessWidget {
  const BottomActionInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, thickness: 1, color: theme.hairline),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
            child: child,
          ),
        ],
      ),
    );
  }
}
