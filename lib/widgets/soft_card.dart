import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Subtle grouping surface: a warm tint and a hairline, no shadow. Used only
/// where content genuinely belongs together; whitespace does the job
/// elsewhere.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.cardWash,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: theme.hairline),
      ),
      child: child,
    );
  }
}
