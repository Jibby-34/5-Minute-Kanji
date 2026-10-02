import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/review.dart';
import '../../core/models/start_of_day.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../repositories/progress_repository.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/centered_copy.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/streak_mark.dart';

/// Shown once, in place of the usual session summary, after the first sitting.
///
/// Every number comes from what the user just did; a line is left out rather
/// than filled with a zero.
class FirstSessionCompleteScreen extends StatefulWidget {
  const FirstSessionCompleteScreen({
    super.key,
    required this.summary,
    required this.onContinue,
    this.startOfDay = StartOfDay.defaults,
  });

  final SessionSummary summary;
  final StartOfDay startOfDay;
  final VoidCallback onContinue;

  @override
  State<FirstSessionCompleteScreen> createState() =>
      _FirstSessionCompleteScreenState();
}

class _FirstSessionCompleteScreenState
    extends State<FirstSessionCompleteScreen> {
  int _learned = 0;
  int _streak = 1;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final progress = context.read<ProgressRepository>();
    try {
      final daily = (await progress.getDailyNewKanji()).forDay(
        DateTime.now(),
        startOfDay: widget.startOfDay,
      );
      final streak = await progress.getStreak();
      if (!mounted) return;
      setState(() {
        _learned = daily.count;
        _streak = streak.current < 1 ? 1 : streak.current;
      });
    } catch (_) {
      // Keep the screen up without stats rather than fail the first session.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reviews = widget.summary.reviewedCount - _learned;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: CenteredCopy(
                horizontalPadding: 24,
                children: [
                  _FadeIn(
                    child: Text(
                      'Day 1 complete!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${formatSessionDuration(widget.summary.duration)} '
                    'well spent.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.mutedText,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_learned > 0)
                    Text(
                      _learned == 1 ? '1 kanji learned' : '$_learned kanji learned',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (reviews > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      reviews == 1
                          ? '1 review completed'
                          : '$reviews reviews completed',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.mutedText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  StreakMark(streak: _streak),
                ],
              ),
            ),
            BottomActionInset(
              child: PrimaryButton(
                label: 'Continue',
                onPressed: widget.onContinue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
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
      child: child,
    );
  }
}
