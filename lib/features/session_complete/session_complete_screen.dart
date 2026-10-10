import 'package:flutter/material.dart';

import '../../core/models/review.dart';
import '../../core/models/start_of_day.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/time_format.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/soft_card.dart';

/// Quiet summary after a study sitting.
///
/// Counts and the next review are taken from [summary] as the session
/// recorded them. This screen only arranges them.
class SessionCompleteScreen extends StatelessWidget {
  const SessionCompleteScreen({
    super.key,
    required this.summary,
    this.startOfDay = StartOfDay.defaults,
    this.clock,
  });

  final SessionSummary summary;
  final StartOfDay startOfDay;

  /// Instant used to phrase [SessionSummary.nextReviewAt]. Defaults to now.
  final Clock? clock;

  @override
  Widget build(BuildContext context) {
    final now = clock?.call() ?? DateTime.now();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final compact =
                      constraints.maxHeight < 640 || textScale > 1.15;
                  return _CompletionBody(
                    summary: summary,
                    startOfDay: startOfDay,
                    now: now,
                    compact: compact,
                  );
                },
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

class _CompletionBody extends StatelessWidget {
  const _CompletionBody({
    required this.summary,
    required this.startOfDay,
    required this.now,
    required this.compact,
  });

  final SessionSummary summary;
  final StartOfDay startOfDay;
  final DateTime now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 20.0 : 28.0;
    final top = compact ? 16.0 : 32.0;
    const bottom = 20.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = (constraints.maxHeight - top - bottom).clamp(
          0.0,
          double.infinity,
        );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, top, 24, bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            // Sit the summary above the midpoint. When it no longer fits,
            // the extra constraint drops away and the page scrolls.
            child: Align(
              alignment: const Alignment(0, -0.28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TweenAnimationBuilder<double>(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CompletionHeader(
                        duration: summary.duration,
                        note: _completionNote(summary),
                        compact: compact,
                      ),
                      SizedBox(height: gap),
                      _ReviewPanel(summary: summary),
                      SizedBox(height: gap),
                      _NextReview(
                        nextReviewAt: summary.nextReviewAt,
                        now: now,
                        startOfDay: startOfDay,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompletionHeader extends StatelessWidget {
  const _CompletionHeader({
    required this.duration,
    required this.note,
    required this.compact,
  });

  final Duration duration;
  final String note;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = compact ? 8.0 : 12.0;

    return Column(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.sageWash,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check, size: 20, color: theme.sageInk),
          ),
        ),
        SizedBox(height: step),
        Text(
          'Nice work.',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        SizedBox(height: step),
        Text(
          formatSessionDuration(duration),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.mutedText,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
        SizedBox(height: step),
        Text(
          note,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.mutedText,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final againNote = _againNote(summary);

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
      child: Column(
        children: [
          Text(
            '${summary.reviewedCount}',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.8,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'kanji reviewed',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.mutedText,
              fontWeight: FontWeight.w400,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, thickness: 1, color: theme.hairline),
          const SizedBox(height: 6),
          _ResultRow(
            icon: Icons.check,
            wash: theme.sageWash,
            ink: theme.sageInk,
            label: 'Successful',
            count: summary.successfulCount,
          ),
          _ResultRow(
            icon: Icons.refresh,
            wash: theme.warmBrownWash,
            ink: theme.warmBrownInk,
            label: 'Need another look',
            count: summary.againCount,
            detail: againNote,
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.wash,
    required this.ink,
    required this.label,
    required this.count,
    this.detail,
  });

  final IconData icon;
  final Color wash;
  final Color ink;
  final String label;
  final int count;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ToneMark(icon: icon, wash: wash, ink: ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.mutedText,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$count',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToneMark extends StatelessWidget {
  const _ToneMark({required this.icon, required this.wash, required this.ink});

  final IconData icon;
  final Color wash;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: ink),
      ),
    );
  }
}

class _NextReview extends StatelessWidget {
  const _NextReview({
    required this.nextReviewAt,
    required this.now,
    required this.startOfDay,
  });

  final DateTime? nextReviewAt;
  final DateTime now;
  final StartOfDay startOfDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timing = _leadIn(
      formatNextReview(nextReviewAt, now, startOfDay: startOfDay),
    );

    return Column(
      children: [
        ExcludeSemantics(
          child: Icon(Icons.schedule_rounded, size: 18, color: theme.mutedText),
        ),
        const SizedBox(height: 8),
        Text(
          'Next review.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.mutedText,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          timing,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

String _completionNote(SessionSummary summary) {
  if (summary.reviewedCount == 0) return 'Nothing to review this time.';
  return 'A little progress goes a long way.';
}

String? _againNote(SessionSummary summary) {
  if (summary.againCount > 0) return null;
  if (summary.reviewedCount == 0) return 'No reviews to revisit.';
  return 'All caught up.';
}

String _leadIn(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
