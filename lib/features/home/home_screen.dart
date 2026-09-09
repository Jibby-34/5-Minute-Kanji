import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/models/start_of_day.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/time_format.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';
import '../kanji_list/kanji_list_screen.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';
import 'home_controller.dart';

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

  Future<void> _startReview({required bool practice}) async {
    final home = context.read<HomeController>();
    final cards = await home.cardsForSession(practice: practice);
    if (!mounted) return;
    if (cards.isEmpty) {
      await home.load(showLoading: false);
      return;
    }

    await Navigator.of(context).push(
      AppRoutes.session(
        context,
        ReviewScreen(cards: cards, isPractice: practice, config: home.config),
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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: home.loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Column(
                children: [
                  _HomeNavBar(
                    onOpenSettings: _openSettings,
                    onOpenKanjiList: _openKanjiList,
                  ),
                  Expanded(
                    child: _HomeCanvas(home: home, now: now),
                  ),
                  BottomActionInset(
                    horizontalPadding: 16,
                    child: PrimaryButton(
                      label: home.isCaughtUp
                          ? 'Practice Anyway'
                          : 'Start Review',
                      onPressed: () => _startReview(practice: home.isCaughtUp),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _HomeNavBar extends StatelessWidget {
  const _HomeNavBar({
    required this.onOpenSettings,
    required this.onOpenKanjiList,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenKanjiList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurface.withValues(alpha: 0.72);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: IconTheme(
        data: IconThemeData(size: 22, color: iconColor),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Settings',
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Kanji List',
              onPressed: onOpenKanjiList,
              icon: const Icon(Icons.grid_view_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

/// Positions greeting + workload in the upper-middle, with streak near the
/// bottom. Extra height becomes whitespace; short screens shrink gaps first.
class _HomeCanvas extends StatelessWidget {
  const _HomeCanvas({required this.home, required this.now});

  final HomeController home;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final compact = height < 500 || textScale > 1.25;
        final topGap = (height * (compact ? 0.06 : 0.11)).clamp(12.0, 88.0);
        final streakBottomGap = (height * (compact ? 0.03 : 0.045)).clamp(
          8.0,
          28.0,
        );
        final numberSize = (height * 0.07).clamp(42.0, 48.0);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    SizedBox(height: topGap),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _StudyPanel(
                        home: home,
                        now: now,
                        compact: compact,
                        numberSize: numberSize,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(top: 20, bottom: streakBottomGap),
                  child: _StreakMark(streak: home.streak),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StudyPanel extends StatelessWidget {
  const _StudyPanel({
    required this.home,
    required this.now,
    required this.compact,
    required this.numberSize,
  });

  final HomeController home;
  final DateTime now;
  final bool compact;
  final double numberSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verticalPad = compact ? 16.0 : 22.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StationeryRule(),
        Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPad, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                greetingFor(now),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.mutedText,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                  height: 1.3,
                ),
              ),
              SizedBox(height: compact ? 12 : 16),
              home.isCaughtUp
                  ? _CaughtUpCopy(
                      nextReviewAt: home.nextReviewAt,
                      now: now,
                      startOfDay: home.startOfDay,
                      compact: compact,
                      numberSize: numberSize,
                    )
                  : _WorkloadCopy(
                      home: home,
                      compact: compact,
                      numberSize: numberSize,
                    ),
            ],
          ),
        ),
        const _StationeryRule(),
      ],
    );
  }
}

class _WorkloadCopy extends StatelessWidget {
  const _WorkloadCopy({
    required this.home,
    required this.compact,
    required this.numberSize,
  });

  final HomeController home;
  final bool compact;
  final double numberSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newCount = home.newRemainingToday;
    final reviews = home.dueCount;
    final showNew = newCount > 0;
    final count = showNew ? newCount : reviews;
    final label = showNew
        ? 'kanji remaining today'
        : reviews == 1
        ? 'review remaining today'
        : 'reviews remaining today';
    final reviewLine = showNew && reviews > 0
        ? (reviews == 1 ? '1 review' : '$reviews reviews')
        : null;
    final metaStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.mutedText,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.35,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WorkloadNumber(count: count, size: numberSize),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: compact ? 18 : 19,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        SizedBox(height: compact ? 10 : 14),
        if (reviewLine != null) ...[
          Text(reviewLine, textAlign: TextAlign.center, style: metaStyle),
          const SizedBox(height: 4),
        ],
        Text(
          '~${home.estimatedMinutes} min',
          textAlign: TextAlign.center,
          style: metaStyle,
        ),
      ],
    );
  }
}

class _CaughtUpCopy extends StatelessWidget {
  const _CaughtUpCopy({
    required this.nextReviewAt,
    required this.now,
    required this.startOfDay,
    required this.compact,
    required this.numberSize,
  });

  final DateTime? nextReviewAt;
  final DateTime now;
  final StartOfDay startOfDay;
  final bool compact;
  final double numberSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metaStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.mutedText,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.35,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WorkloadNumber(count: 0, size: numberSize),
        const SizedBox(height: 4),
        Text(
          'kanji remaining today',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: compact ? 18 : 19,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        SizedBox(height: compact ? 10 : 14),
        Text(
          "You're all caught up.",
          textAlign: TextAlign.center,
          style: metaStyle,
        ),
        const SizedBox(height: 4),
        Text(
          'Next review: ${formatNextReview(nextReviewAt, now, startOfDay: startOfDay)}',
          textAlign: TextAlign.center,
          style: metaStyle,
        ),
      ],
    );
  }
}

class _WorkloadNumber extends StatelessWidget {
  const _WorkloadNumber({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: AppTypography.kanji(
          color: Theme.of(context).colorScheme.onSurface,
          size: size,
        ),
      ),
    );
  }
}

class _StreakMark extends StatelessWidget {
  const _StreakMark({required this.streak});

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

class _StationeryRule extends StatelessWidget {
  const _StationeryRule();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).hairline,
      child: const SizedBox(height: 1, width: double.infinity),
    );
  }
}
