import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The streak line used on Home and after a finished session.
class StreakMark extends StatelessWidget {
  const StreakMark({super.key, required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const valueStyle = 17.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '🔥',
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: valueStyle,
            height: 1,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$streak',
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: valueStyle,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'day streak',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            color: theme.mutedText,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
