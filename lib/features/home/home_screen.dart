import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/start_of_day.dart';
import '../../core/models/study_allocation.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../widgets/streak_mark.dart';
import '../kanji_list/kanji_list_screen.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';
import 'home_controller.dart';

const _page = Color(0xFFF3EFE7);
const _ink = Color(0xFF1C1A17);
const _muted = Color(0xFF5C574E);
const _line = Color(0xFFD9D2C3);
const _chip = Color(0xFFE9E2D2);
const _flame = Color(0xFFC9622B);

/// A step lighter than the page, matching the welcome plan card.
const _planFill = Color(0xFFFBF9F5);

/// New-kanji share of the plan bar. The same indigo as the welcome example.
const _newKanji = Color(0xFF8E96C4);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<HomeController>().load(showLoading: false);
    }
  }

  Future<void> _startReview({required bool studyAnyway}) async {
    final home = context.read<HomeController>();
    final cards = await home.cardsForSession(studyAnyway: studyAnyway);
    if (!mounted) return;
    if (cards.isEmpty) {
      await home.load(showLoading: false);
      return;
    }

    await Navigator.of(context).push(
      AppRoutes.session(
        context,
        ReviewScreen(
          cards: cards,
          isStudyAnyway: studyAnyway,
          config: home.config,
        ),
      ),
    );
    if (mounted) {
      await context.read<HomeController>().load(showLoading: false);
    }
  }

  Future<void> _openKanjiList() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const KanjiListScreen()));
    if (mounted) {
      await context.read<HomeController>().load(showLoading: false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    if (mounted) {
      await context.read<HomeController>().load(showLoading: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeController>();
    final now = DateTime.now();
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        bottom: false,
        child: home.loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + bottomInset),
                child: _HomeBody(
                  home: home,
                  now: now,
                  onOpenSettings: _openSettings,
                  onOpenKanjiList: _openKanjiList,
                  onStart: () =>
                      _startReview(studyAnyway: home.studyAnywayAvailable),
                ),
              ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.home,
    required this.now,
    required this.onOpenSettings,
    required this.onOpenKanjiList,
    required this.onStart,
  });

  final HomeController home;
  final DateTime now;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenKanjiList;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final action = home.studyAnywayAvailable
        ? 'Optional Practice'
        : home.recommendedCount > 0
        ? 'Start Review'
        : null;

    return Column(
      children: [
        _HomeHeader(
          streak: home.streak,
          onOpenSettings: onOpenSettings,
          onOpenKanjiList: onOpenKanjiList,
        ),
        Expanded(
          child: _HomeMiddle(home: home, now: now),
        ),
        if (action != null) _StartButton(label: action, onPressed: onStart),
      ],
    );
  }
}

/// Settings, days studied, and the kanji list. The count lives here so the
/// study card can stay about today's sitting.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.streak,
    required this.onOpenSettings,
    required this.onOpenKanjiList,
  });

  final int streak;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenKanjiList;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          _NavIconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined, size: 22, color: _ink),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _StreakChip(streak: streak),
              ),
            ),
          ),
          _NavIconButton(
            tooltip: 'Kanji list',
            onPressed: onOpenKanjiList,
            icon: const SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(painter: _KanjiListIconPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: _ink,
          fixedSize: const Size(48, 48),
          minimumSize: const Size(48, 48),
          maximumSize: const Size(48, 48),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = theme.textTheme.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _ink,
      height: 1,
    );
    final caption = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: _muted,
      height: 1,
    );

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _chip,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExcludeSemantics(
            child: Icon(Icons.local_fire_department, size: 18, color: _flame),
          ),
          const SizedBox(width: 7),
          Text('$streak', style: value),
          const SizedBox(width: 7),
          Text(daysStudiedLabel(streak), style: caption),
        ],
      ),
    );
  }
}

/// Four rounded squares. A stroke icon, so it matches the settings outline.
class _KanjiListIconPainter extends CustomPainter {
  const _KanjiListIconPainter();

  static const _stroke = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeJoin = StrokeJoin.round;

    const gap = 3.0;
    final box = (size.shortestSide - gap) / 2;
    final radius = Radius.circular(box * 0.28);
    for (var row = 0; row < 2; row++) {
      for (var column = 0; column < 2; column++) {
        final rect = Rect.fromLTWH(
          column * (box + gap),
          row * (box + gap),
          box,
          box,
        ).deflate(_stroke / 2);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KanjiListIconPainter oldDelegate) => false;
}

/// Greeting and today's card, centered in whatever height is left. Short
/// screens scroll instead of overflowing.
class _HomeMiddle extends StatelessWidget {
  const _HomeMiddle({required this.home, required this.now});

  final HomeController home;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    greetingFor(now),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _muted,
                      fontSize: 21,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _DailyStudyCard(home: home, now: now),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DailyStudyCard extends StatelessWidget {
  const _DailyStudyCard({required this.home, required this.now});

  final HomeController home;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (home.studyAnywayAvailable) {
      return _StatusCard(
        title: "You're done for today!",
        meta: 'Nice work!',
        trial: home.trialProgressLabel,
      );
    }

    if (home.recommendedCount <= 0) {
      return _StatusCard(
        title: "You're all caught up.",
        trial: home.trialProgressLabel,
        footer: _NextReviewLine(
          nextReviewAt: home.nextReviewAt,
          now: now,
          startOfDay: home.startOfDay,
        ),
      );
    }

    return _StudyPlanCard(
      allocation: home.studyAllocation,
      trial: home.trialProgressLabel,
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _planFill,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: _line, width: 1.5),
      ),
      child: child,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.title, this.meta, this.trial, this.footer});

  final String title;
  final String? meta;
  final String? trial;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _HomeCard(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: _ink,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          if (meta != null) ...[
            const SizedBox(height: 6),
            Text(
              meta!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _muted,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ],
          if (trial != null) ...[
            const SizedBox(height: 10),
            Text(
              trial!,
              textAlign: TextAlign.center,
              style: _trialStyle(theme),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, thickness: 1, color: _line),
            const SizedBox(height: 14),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// Today's sitting: total time, the split between reviews and new kanji,
/// and the count and estimate for each.
class _StudyPlanCard extends StatelessWidget {
  const _StudyPlanCard({required this.allocation, this.trial});

  final StudyAllocation allocation;
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

    return _HomeCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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

class _StartButton extends StatelessWidget {
  const _StartButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.indigo,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(60),
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Reassurance that spaced repetition is being handled, kept deliberately
/// quiet.
class _NextReviewLine extends StatelessWidget {
  const _NextReviewLine({
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const ExcludeSemantics(
          child: Icon(Icons.schedule_rounded, size: 15, color: _muted),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            'Next review: '
            '${formatNextReview(nextReviewAt, now, startOfDay: startOfDay)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _muted,
              fontSize: 14,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
