import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/review.dart';
import '../../core/models/start_of_day.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../repositories/progress_repository.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/streak_mark.dart';
import 'widgets/onboarding_scaffold.dart';

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

    return OnboardingScaffold(
      action: PrimaryButton(label: 'Continue', onPressed: widget.onContinue),
      content: (context, height) {
        return _FadeIn(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OnboardingHeadline(
                title: 'Day 1 complete!',
                subtitle:
                    '${formatSessionDuration(widget.summary.duration)} '
                    'well spent.',
              ),
              SizedBox(height: (height * 0.07).clamp(26.0, 44.0)),
              if (_learned > 0 || reviews > 0)
                SoftCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 26,
                  ),
                  child: Column(
                    children: [
                      if (_learned > 0)
                        OnboardingStat(
                          value: '$_learned',
                          label: 'kanji learned',
                        )
                      else
                        OnboardingStat(
                          value: '$reviews',
                          label: reviews == 1
                              ? 'review completed'
                              : 'reviews completed',
                        ),
                      if (_learned > 0 && reviews > 0) ...[
                        const SizedBox(height: 18),
                        const HairlineMark(width: 56),
                        const SizedBox(height: 18),
                        Text(
                          reviews == 1
                              ? '1 review completed'
                              : '$reviews reviews completed',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.mutedText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              SizedBox(height: (height * 0.05).clamp(20.0, 32.0)),
              _StreakChip(streak: _streak),
            ],
          ),
        );
      },
    );
  }
}

/// The streak, set apart so it reads as a reward rather than another stat.
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: theme.cardWash,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        border: Border.all(color: theme.hairline),
      ),
      child: StreakMark(streak: streak),
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
