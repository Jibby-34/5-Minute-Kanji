import 'package:flutter/material.dart';

import '../../core/models/study_allocation.dart';
import '../../core/models/study_day_type.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';

const _ink = Color(0xFF1C1A17);
const _muted = Color(0xFF5C574E);
const _line = Color(0xFFD9D2C3);

/// A step lighter than the page, matching the welcome plan card.
const _planFill = Color(0xFFFBF9F5);

/// New-kanji share of the plan bar. The same indigo as the welcome example.
const _newKanji = Color(0xFF8E96C4);

/// Today's sitting: total time, the split between reviews and new kanji,
/// and the count and estimate for each.
///
/// Home and the Reinforcement Day debugger both build this widget. A preview
/// passes its own [allocation] and [dayType]; it does not replace the plan
/// Home is showing.
class StudyPlanCard extends StatelessWidget {
  const StudyPlanCard({
    super.key,
    required this.allocation,
    required this.dayType,
    this.trial,
  });

  final StudyAllocation allocation;
  final StudyDayType dayType;
  final String? trial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = allocation;
    final total = plan.totalKnown
        ? formatPlanDuration(
            roundPlanSeconds(plan.reviewSeconds) +
                roundPlanSeconds(plan.newSeconds),
          )
        : _unavailableTime;

    return _PlanShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DayTypeHeader(dayType: dayType),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: width.isFinite ? width : 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('STUDY PLAN', style: _headingStyle(theme)),
                      const SizedBox(width: 16),
                      Text(total, style: _totalStyle(theme)),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          _PlanBar(allocation: plan),
          const SizedBox(height: 16),
          _PlanCategory(
            color: AppColors.indigo,
            label: 'Reviews',
            count: _cardsLabel(plan.reviewCards),
            time: _categoryTime(
              plan.reviewSeconds,
              known: plan.reviewTimeKnown,
            ),
          ),
          const SizedBox(height: 10),
          _PlanCategory(
            color: _newKanji,
            label: 'New kanji',
            count: _cardsLabel(plan.newCards),
            time: _categoryTime(plan.newSeconds, known: plan.newTimeKnown),
          ),
          if (trial != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 1, color: _line),
            const SizedBox(height: 10),
            _TrialProgress(label: trial!),
          ],
        ],
      ),
    );
  }
}

class _PlanShell extends StatelessWidget {
  const _PlanShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: _planFill,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: _line, width: 1.5),
      ),
      child: child,
    );
  }
}

class _DayTypeHeader extends StatelessWidget {
  const _DayTypeHeader({required this.dayType});

  final StudyDayType dayType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reinforcement = dayType == StudyDayType.reinforcement;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DAY TYPE', style: _headingStyle(theme)),
        const SizedBox(height: 2),
        Text(dayType.label, style: _dayTypeStyle(theme)),
        if (reinforcement) ...[
          const SizedBox(height: 3),
          Text(StudyDayType.reinforcementNote, style: _dayNoteStyle(theme)),
        ],
      ],
    );
  }
}

TextStyle _dayTypeStyle(ThemeData theme) {
  return (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
    color: _ink,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}

TextStyle _dayNoteStyle(ThemeData theme) {
  return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    color: _muted,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
}

TextStyle _headingStyle(ThemeData theme) {
  return (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
    color: _muted,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    height: 1.2,
  );
}

TextStyle _totalStyle(ThemeData theme) {
  return (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
    color: AppColors.indigo,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1,
  );
}

TextStyle _trialStyle(ThemeData theme) {
  return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    color: _muted,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
}

const _unavailableTime = '\u2014';

String _cardsLabel(int count) {
  final cards = count < 0 ? 0 : count;
  return cards == 1 ? '1 card' : '$cards cards';
}

String _categoryTime(int seconds, {required bool known}) {
  if (!known) return _unavailableTime;
  return formatPlanDuration(seconds < 0 ? 0 : seconds);
}

class _PlanCategory extends StatelessWidget {
  const _PlanCategory({
    required this.color,
    required this.label,
    required this.count,
    required this.time,
  });

  final Color color;
  final String label;
  final String count;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = theme.textTheme.bodyLarge?.copyWith(
      color: _ink,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    final countStyle = theme.textTheme.bodyLarge?.copyWith(
      color: _ink,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    final timeStyle = theme.textTheme.bodyMedium?.copyWith(
      color: _muted,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.2,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: _PlanDot(color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: name,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(count, maxLines: 1, softWrap: false, style: countStyle),
            const SizedBox(height: 1),
            Text(time, maxLines: 1, softWrap: false, style: timeStyle),
          ],
        ),
      ],
    );
  }
}

/// The stored trial line is `0 / 50 free kanji learned`. The plan shows the
/// words and the fraction on one row. An unexpected string stays intact.
class _TrialProgress extends StatelessWidget {
  const _TrialProgress({required this.label});

  final String label;

  static final _count = RegExp(r'^(\d+ / \d+) free kanji learned$');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = _count.firstMatch(label);
    final style = _trialStyle(theme);
    if (match == null) {
      return Text(label, style: style);
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            'Free kanji learned',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 8),
        Text(match.group(1)!, maxLines: 1, softWrap: false, style: style),
      ],
    );
  }
}

class _PlanDot extends StatelessWidget {
  const _PlanDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: 10,
        height: 10,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// Time split for the sitting. Segments follow estimated seconds, and a
/// category with no time is left out so the bar does not invent a share.
class _PlanBar extends StatelessWidget {
  const _PlanBar({required this.allocation});

  final StudyAllocation allocation;

  static const gap = 3.0;
  static const minimum = 8.0;
  static const height = 12.0;

  @override
  Widget build(BuildContext context) {
    final plan = allocation;
    final described = !plan.totalKnown || plan.totalSeconds <= 0
        ? 'Estimated time split unavailable'
        : 'Estimated time split. '
              'Reviews ${formatPlanDurationSpoken(plan.reviewSeconds)}. '
              'New kanji ${formatPlanDurationSpoken(plan.newSeconds)}.';

    return Semantics(
      label: described,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: plan.totalKnown && plan.totalSeconds > 0
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final widths = plan.segmentWidths(
                    width: constraints.maxWidth,
                    gap: gap,
                    minimum: minimum,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widths.reviews > 0)
                        _BarSegment(
                          width: widths.reviews,
                          color: AppColors.indigo,
                        ),
                      if (widths.reviews > 0 && widths.fresh > 0)
                        const SizedBox(width: gap),
                      if (widths.fresh > 0)
                        _BarSegment(width: widths.fresh, color: _newKanji),
                    ],
                  );
                },
              )
            : const DecoratedBox(
                decoration: BoxDecoration(
                  color: _line,
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
              ),
      ),
    );
  }
}

class _BarSegment extends StatelessWidget {
  const _BarSegment({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
