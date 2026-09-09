import 'package:flutter/material.dart';

import '../../core/models/review.dart';
import '../../core/models/start_of_day.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';

class SessionCompleteScreen extends StatelessWidget {
  const SessionCompleteScreen({
    super.key,
    required this.summary,
    this.startOfDay = StartOfDay.defaults,
  });

  final SessionSummary summary;
  final StartOfDay startOfDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    const kanjiLabel = 'kanji reviewed';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 8 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        'Nice.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      formatSessionDuration(summary.duration),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.mutedText,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      '${summary.reviewedCount} $kanjiLabel',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${summary.successfulCount} successful',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.mutedText,
                      ),
                    ),
                    Text(
                      '${summary.againCount} need another look',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.mutedText,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Next review: ${formatNextReview(summary.nextReviewAt, now, startOfDay: startOfDay)}',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            BottomActionInset(
              child: PrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
