import 'package:flutter/material.dart';

import '../../core/models/review.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/soft_card.dart';

/// Quiet summary after a study sitting.
///
/// Counts are taken from [summary] as the session recorded them. This
/// screen only arranges them.
class SessionCompleteScreen extends StatelessWidget {
  const SessionCompleteScreen({super.key, required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
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
                  return _CompletionBody(summary: summary, compact: compact);
                },
              ),
            ),
            BottomActionInset(
              child: summary.canContinue
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PrimaryButton(
                          label: 'Done',
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                        const SizedBox(height: 10),
                        SecondaryButton(
                          label: 'Optional Practice',
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ],
                    )
                  : PrimaryButton(
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
  const _CompletionBody({required this.summary, required this.compact});

  final SessionSummary summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 22.0 : 36.0;
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
                      _ReviewPanel(summary: summary, compact: compact),
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
    final step = compact ? 8.0 : 14.0;
    final mark = compact ? 44.0 : 56.0;

    return Column(
      children: [
        ExcludeSemantics(
          child: Container(
            width: mark,
            height: mark,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.sageWash,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              size: compact ? 20 : 24,
              color: theme.sageInk,
            ),
          ),
        ),
        SizedBox(height: step),
        Text(
          "You're done for today!",
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
          '${formatSessionDuration(duration)} today',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.mutedText,
            fontSize: compact ? 16 : 18,
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
            fontSize: compact ? 14 : 16,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({required this.summary, required this.compact});

  final SessionSummary summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final againNote = _againNote(summary);

    return SoftCard(
      padding: compact
          ? const EdgeInsets.fromLTRB(18, 22, 18, 10)
          : const EdgeInsets.fromLTRB(20, 26, 20, 14),
      child: Column(
        children: [
          Text(
            '${summary.reviewedCount}',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: compact ? 36 : 48,
              fontWeight: FontWeight.w600,
              letterSpacing: compact ? -0.8 : -1.2,
              height: 1,
            ),
          ),
          SizedBox(height: compact ? 6 : 10),
          Text(
            'kanji reviewed',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.mutedText,
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w400,
              height: 1.2,
            ),
          ),
          SizedBox(height: compact ? 16 : 20),
          Divider(height: 1, thickness: 1, color: theme.hairline),
          SizedBox(height: compact ? 6 : 8),
          _ResultRow(
            icon: Icons.check,
            wash: theme.sageWash,
            ink: theme.sageInk,
            label: 'Successful',
            count: summary.successfulCount,
            compact: compact,
          ),
          _ResultRow(
            icon: Icons.refresh,
            wash: theme.warmBrownWash,
            ink: theme.warmBrownInk,
            label: 'Need another look',
            count: summary.againCount,
            detail: againNote,
            compact: compact,
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
    required this.compact,
    this.detail,
  });

  final IconData icon;
  final Color wash;
  final Color ink;
  final String label;
  final int count;
  final bool compact;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mark = compact ? 32.0 : 36.0;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ToneMark(icon: icon, wash: wash, ink: ink, size: mark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: compact ? 16 : 17,
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
                      fontSize: compact ? 14 : 15,
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
              fontSize: compact ? 16 : 18,
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
  const _ToneMark({
    required this.icon,
    required this.wash,
    required this.ink,
    required this.size,
  });

  final IconData icon;
  final Color wash;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
        child: Icon(icon, size: size / 2, color: ink),
      ),
    );
  }
}

String _completionNote(SessionSummary summary) {
  if (summary.reviewedCount == 0) return 'Nothing to review this time.';
  return 'Nice work!';
}

String? _againNote(SessionSummary summary) {
  if (summary.againCount > 0) return null;
  if (summary.reviewedCount == 0) return 'No reviews to revisit.';
  return 'All caught up.';
}
