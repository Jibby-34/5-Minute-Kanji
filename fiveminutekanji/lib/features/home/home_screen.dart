import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/app_routes.dart';
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
                    child: Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                ),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 360,
                                      ),
                                      child: _StudyPanel(home: home, now: now),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
                          child: _StreakMark(streak: home.streak),
                        ),
                      ],
                    ),
                  ),
                  BottomActionInset(
                    child: PrimaryButton(
                      label: home.isCaughtUp
                          ? 'Practice Anyway'
                          : 'Start Review',
                      height: 56,
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

class _StudyPanel extends StatelessWidget {
  const _StudyPanel({required this.home, required this.now});

  final HomeController home;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StationeryRule(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                greetingFor(now),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.mutedText,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 22),
              home.isCaughtUp
                  ? _CaughtUpCopy(nextReviewAt: home.nextReviewAt, now: now)
                  : _WorkloadCopy(home: home),
            ],
          ),
        ),
        const _StationeryRule(),
      ],
    );
  }
}

class _WorkloadCopy extends StatelessWidget {
  const _WorkloadCopy({required this.home});

  final HomeController home;

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: AppTypography.kanji(
              color: theme.colorScheme.onSurface,
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        if (reviewLine != null) ...[
          const SizedBox(height: 12),
          Text(
            reviewLine,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.mutedText,
              fontWeight: FontWeight.w400,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          '~${home.estimatedMinutes} min',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.mutedText,
            fontWeight: FontWeight.w400,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _CaughtUpCopy extends StatelessWidget {
  const _CaughtUpCopy({required this.nextReviewAt, required this.now});

  final DateTime? nextReviewAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "You're all caught up.",
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Next review: ${formatNextReview(nextReviewAt, now)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.mutedText,
            fontWeight: FontWeight.w400,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _StreakMark extends StatelessWidget {
  const _StreakMark({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('🔥', style: theme.textTheme.titleMedium?.copyWith(height: 1)),
        const SizedBox(width: 8),
        Text(
          '$streak',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'day streak',
          style: theme.textTheme.bodyLarge?.copyWith(
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
    return Container(height: 1, color: Theme.of(context).hairline);
  }
}
