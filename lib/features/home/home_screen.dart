import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/start_of_day.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/time_format.dart';
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
const _card = Color(0xFFEDE6D8);

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
    final workload = _Workload.of(home);

    return Column(
      children: [
        _HomeHeader(
          streak: home.streak,
          onOpenSettings: onOpenSettings,
          onOpenKanjiList: onOpenKanjiList,
        ),
        Expanded(
          child: _HomeMiddle(home: home, now: now, workload: workload),
        ),
        if (workload.action case final action?)
          _StartButton(label: action, onPressed: onStart),
      ],
    );
  }
}

/// Settings, the streak, and the kanji list. The streak lives here so the
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
          Text('day streak', style: caption),
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
  const _HomeMiddle({
    required this.home,
    required this.now,
    required this.workload,
  });

  final HomeController home;
  final DateTime now;
  final _Workload workload;

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
                  const SizedBox(height: 60),
                  _DailyStudyCard(home: home, now: now, workload: workload),
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
  const _DailyStudyCard({
    required this.home,
    required this.now,
    required this.workload,
  });

  final HomeController home;
  final DateTime now;
  final _Workload workload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showNextReview =
        !home.studyAnywayAvailable && home.recommendedCount == 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 40),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          if (workload.title case final title?)
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
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 28),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${workload.count}',
                  textAlign: TextAlign.center,
                  style: AppTypography.kanji(
                    color: _ink,
                    size: 176,
                  ).copyWith(fontWeight: FontWeight.w400, height: 0.85),
                ),
              ),
            ),
            Text(
              workload.label!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: _ink,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              workload.meta,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _muted,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ),
          if (home.trialProgressLabel case final trial?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                trial,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                ),
              ),
            ),
          if (showNextReview) ...[
            const SizedBox(height: 18),
            Divider(height: 1, thickness: 1, color: _line),
            const SizedBox(height: 14),
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

/// Words for the home card. A finished plan reads as done for the day;
/// anything still eligible is optional practice, not remaining work.
class _Workload {
  const _Workload({
    required this.meta,
    this.count,
    this.label,
    this.title,
    this.action,
  });

  final int? count;
  final String? label;
  final String? title;
  final String meta;
  final String? action;

  static String itemsLabel(int count) {
    return count == 1 ? 'study item today' : 'study items today';
  }

  static _Workload of(HomeController home) {
    if (home.studyAnywayAvailable) {
      return const _Workload(
        title: "You're done for today!",
        meta: 'Nice work!',
        action: 'Optional Practice',
      );
    }

    if (home.recommendedCount <= 0) {
      return _Workload(
        count: 0,
        label: itemsLabel(0),
        meta: "You're all caught up.",
      );
    }

    final count = home.studyItemCount;
    return _Workload(
      count: count,
      label: itemsLabel(count),
      meta: '~${home.estimatedMinutes} min',
      action: 'Start Review',
    );
  }
}
