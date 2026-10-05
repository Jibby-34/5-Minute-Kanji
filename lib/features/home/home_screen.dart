import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/start_of_day.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/time_format.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/streak_mark.dart';
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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: home.loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Column(
                children: [
                  _HomeHeader(
                    onOpenSettings: _openSettings,
                    onOpenKanjiList: _openKanjiList,
                  ),
                  Expanded(
                    child: _HomeCanvas(
                      home: home,
                      now: now,
                      onStart: () =>
                          _startReview(studyAnyway: home.studyAnywayAvailable),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Settings and the kanji list sit in the corners as quiet icon buttons, so
/// nothing competes with today's study action.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.onOpenSettings,
    required this.onOpenKanjiList,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenKanjiList;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          _NavIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onPressed: onOpenSettings,
          ),
          const Spacer(),
          _NavIconButton(
            icon: Icons.grid_view_rounded,
            tooltip: 'Kanji List',
            onPressed: onOpenKanjiList,
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

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: theme.cardWash,
          foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.75),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(color: theme.hairline),
          ),
        ),
      ),
    );
  }
}

/// Greeting, today's study card and the streak, composed around the middle of
/// the screen. Extra height becomes even whitespace; short screens shrink the
/// gaps first and scroll only as a last resort.
class _HomeCanvas extends StatelessWidget {
  const _HomeCanvas({
    required this.home,
    required this.now,
    required this.onStart,
  });

  final HomeController home;
  final DateTime now;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final compact = height < 540 || textScale > 1.25;
        final greetingGap = (height * (compact ? 0.022 : 0.032)).clamp(
          12.0,
          28.0,
        );
        final streakGap = (height * (compact ? 0.03 : 0.045)).clamp(18.0, 38.0);
        final numberSize = (height * (compact ? 0.11 : 0.125)).clamp(
          60.0,
          100.0,
        );
        final verticalPadding = compact ? 8.0 : 16.0;
        // Sitting a little above the geometric centre keeps the count in the
        // reading zone instead of floating in the middle of the page.
        final topBias = compact ? 0.0 : (height * 0.07).clamp(0.0, 64.0);
        final freeHeight = height - verticalPadding * 2 - bottomInset - topBias;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            24,
            verticalPadding,
            24,
            verticalPadding + bottomInset + topBias,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: freeHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
                SizedBox(height: greetingGap),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _DailyStudyCard(
                    home: home,
                    now: now,
                    compact: compact,
                    numberSize: numberSize,
                    onStart: onStart,
                  ),
                ),
                SizedBox(height: streakGap),
                StreakMark(streak: home.streak),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Everything about today in one place: how much is left, the one action to
/// take, and when the next review lands.
class _DailyStudyCard extends StatelessWidget {
  const _DailyStudyCard({
    required this.home,
    required this.now,
    required this.compact,
    required this.numberSize,
    required this.onStart,
  });

  final HomeController home;
  final DateTime now;
  final bool compact;
  final double numberSize;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workload = _Workload.of(home);
    // The line earns its place once today's planned sitting is finished and
    // there is nothing optional left.
    final showNextReview =
        !home.studyAnywayAvailable && home.recommendedCount == 0;

    return SoftCard(
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 18 : 24,
      ),
      child: Column(
        children: [
          const SectionLabel('Today', align: TextAlign.center),
          SizedBox(height: compact ? 12 : 18),
          _DailyCount(
            count: workload.count,
            size: numberSize,
            caughtUp: home.recommendedCount == 0,
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            workload.label,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: compact ? 19 : 20,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
              height: 1.3,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            workload.meta,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.mutedText,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          if (workload.action case final action?) ...[
            SizedBox(height: compact ? 18 : 24),
            PrimaryButton(label: action, onPressed: onStart),
            if (workload.footnote case final footnote?) ...[
              SizedBox(height: compact ? 10 : 12),
              Text(
                footnote,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.mutedText,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ],
          ],
          if (showNextReview) ...[
            SizedBox(height: compact ? 14 : 18),
            Divider(height: 1, thickness: 1, color: theme.hairline),
            SizedBox(height: compact ? 12 : 14),
            _NextReviewLine(
              nextReviewAt: home.nextReviewAt,
              now: now,
              startOfDay: home.startOfDay,
            ),
          ],
        ],
      ),
    );
  }
}

/// The one number the screen is built around, on a faint paper circle.
class _DailyCount extends StatelessWidget {
  const _DailyCount({
    required this.count,
    required this.size,
    required this.caughtUp,
  });

  final int count;
  final double size;
  final bool caughtUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // Done for the day reads green; work left reads indigo.
    final wash = caughtUp
        ? (dark ? AppColors.darkIndigoWash : AppColors.masteredWash)
        : theme.accentWash;
    final diameter = size * 1.45;

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.square(
          dimension: diameter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  wash.withValues(alpha: 0.55),
                  wash.withValues(alpha: 0),
                ],
                stops: const [0.5, 1],
              ),
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: AppTypography.kanji(
              color: theme.colorScheme.onSurface,
              size: size,
            ),
          ),
        ),
      ],
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
        ExcludeSemantics(
          child: Icon(Icons.schedule_rounded, size: 15, color: theme.mutedText),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            'Next review: '
            '${formatNextReview(nextReviewAt, now, startOfDay: startOfDay)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.mutedText,
              fontSize: 14,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Today's numbers turned into the words the card shows. New kanji lead;
/// reviews take over once the day's new cards are done.
class _Workload {
  const _Workload({
    required this.count,
    required this.label,
    required this.meta,
    this.action,
    this.footnote,
  });

  final int count;
  final String label;
  final String meta;
  final String? action;
  final String? footnote;

  static _Workload of(HomeController home) {
    if (home.studyAnywayAvailable) {
      return const _Workload(
        count: 0,
        label: 'kanji remaining today',
        meta: "You're done for today!",
        action: 'Study Anyway',
        footnote: 'Keep going with other due kanji',
      );
    }

    if (home.recommendedCount <= 0) {
      return const _Workload(
        count: 0,
        label: 'kanji remaining today',
        meta: "You're all caught up.",
      );
    }

    return _Workload(
      count: home.recommendedCount,
      label: 'kanji remaining today',
      meta: '~${home.estimatedMinutes} min',
      action: 'Start Review',
    );
  }
}
