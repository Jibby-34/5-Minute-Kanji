import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/kanji_card.dart';
import '../../core/models/placement.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../services/placement_service.dart';
import '../../widgets/kanji_mark.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../onboarding/widgets/onboarding_scaffold.dart';
import 'placement_controller.dart';

/// Self-check for kanji the user can write from memory.
///
/// Reviews ask for the character, so "known" here means they could produce
/// it, not merely recognize it. Nothing is drawn. A tap moves straight to
/// the next kanji, and nothing marks the answer right or wrong.
class PlacementScreen extends StatelessWidget {
  const PlacementScreen({super.key, required this.onFinished});

  /// Called when the user leaves the results screen.
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          PlacementController(service: context.read<PlacementService>())
            ..load(),
      child: _PlacementView(onFinished: onFinished),
    );
  }
}

class _PlacementView extends StatelessWidget {
  const _PlacementView({required this.onFinished});

  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlacementController>();

    return switch (controller.phase) {
      PlacementPhase.loading || PlacementPhase.saving => const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      PlacementPhase.selfAssessment => _SelfAssessment(
        onContinue: controller.choose,
      ),
      PlacementPhase.intro => _PlacementIntro(controller: controller),
      PlacementPhase.asking => _PlacementQuestion(controller: controller),
      PlacementPhase.results => _PlacementResults(
        summary: controller.summary,
        onFinished: onFinished,
      ),
    };
  }
}

class _AssessmentOption {
  const _AssessmentOption(this.assessment, this.title, this.detail);

  final PlacementSelfAssessment assessment;
  final String title;
  final String detail;
}

const _assessmentOptions = [
  _AssessmentOption(
    PlacementSelfAssessment.newUser,
    "I'm new",
    "I haven't really studied kanji yet.",
  ),
  _AssessmentOption(
    PlacementSelfAssessment.beginner,
    'Beginner',
    'I can write some common kanji from memory.',
  ),
  _AssessmentOption(
    PlacementSelfAssessment.intermediate,
    'Intermediate',
    'I can write quite a few kanji from memory.',
  ),
  _AssessmentOption(
    PlacementSelfAssessment.expert,
    'Expert',
    "I've studied for a long time and can write lots of kanji from memory.",
  ),
];

/// Asks where to start looking. The choice is a guess, not a level.
class _SelfAssessment extends StatefulWidget {
  const _SelfAssessment({required this.onContinue});

  final Future<void> Function(PlacementSelfAssessment assessment) onContinue;

  @override
  State<_SelfAssessment> createState() => _SelfAssessmentState();
}

class _SelfAssessmentState extends State<_SelfAssessment> {
  PlacementSelfAssessment? _selected;
  bool _saving = false;

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null || _saving) return;
    setState(() => _saving = true);
    await widget.onContinue(selected);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 2,
      action: PrimaryButton(
        label: 'Continue',
        onPressed: _selected == null || _saving ? null : _submit,
      ),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const OnboardingHeadline(
              label: 'Placement',
              title: 'How many kanji can you write?',
              subtitle:
                  'From memory. Recognizing a kanji is not the same as being able to write it.',
            ),
            SizedBox(height: (height * 0.05).clamp(20.0, 32.0)),
            for (final option in _assessmentOptions) ...[
              _AssessmentCard(
                option: option,
                selected: _selected == option.assessment,
                onTap: () => setState(() => _selected = option.assessment),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _AssessmentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? theme.accentWash.withValues(alpha: 0.55) : null,
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              border: Border.all(
                color: selected ? primary : theme.hairline,
                width: selected ? 1.6 : 1.2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 18,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.detail,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.mutedText,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 12),
                  _Tick(color: primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(
        Icons.check,
        size: 15,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

class _PlacementIntro extends StatelessWidget {
  const _PlacementIntro({required this.controller});

  final PlacementController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resuming = controller.isResuming;

    return OnboardingScaffold(
      step: 2,
      action: PrimaryButton(
        label: resuming ? 'Continue' : 'Start Placement Test',
        onPressed: controller.start,
      ),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LevelRamp(size: (height * 0.15).clamp(48.0, 88.0)),
            SizedBox(height: height * 0.08),
            OnboardingHeadline(
              label: 'Placement',
              title: "Let's find your starting point",
              subtitle: resuming
                  ? 'Pick up where you left off.\n'
                        'Count a kanji only if you could write it from memory.'
                  : "We'll show you some kanji.\n"
                        'Count one only if you could write it from memory.',
            ),
            const SizedBox(height: 14),
            Text(
              "Recognizing it isn't enough, and you won't have to draw.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.mutedText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'It only takes a couple minutes.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.mutedText,
                height: 1.4,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Three kanji fading out: easy to hard, which is what the test is looking for.
class _LevelRamp extends StatelessWidget {
  const _LevelRamp({required this.size});

  final double size;

  static const _characters = ['日', '校', '議'];
  static const _alphas = [1.0, 0.45, 0.18];

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;

    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < _characters.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Text(
                _characters[index],
                style: AppTypography.kanji(
                  color: ink.withValues(alpha: _alphas[index]),
                  size: size,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlacementQuestion extends StatelessWidget {
  const _PlacementQuestion({required this.controller});

  final PlacementController controller;

  Future<void> _answer(BuildContext context, {required bool known}) async {
    HapticFeedback.lightImpact();
    await controller.answer(known: known);
  }

  @override
  Widget build(BuildContext context) {
    final card = controller.question;
    if (card == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return OnboardingScaffold(
      header: _PlacementProgress(controller: controller),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: 'I can write it',
            onPressed: () => _answer(context, known: true),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: "I can't write it",
            onPressed: () => _answer(context, known: false),
          ),
        ],
      ),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SectionLabel(
              'Could you write this from memory?',
              align: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Recognizing it isn't enough.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).mutedText,
                height: 1.4,
              ),
            ),
            SizedBox(height: height * 0.04),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _PlacementKanji(
                key: ValueKey(card.id),
                card: card,
                size: (height * 0.3).clamp(96.0, 164.0),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlacementKanji extends StatelessWidget {
  const _PlacementKanji({super.key, required this.card, required this.size});

  final KanjiCard card;
  final double size;

  @override
  Widget build(BuildContext context) {
    return KanjiMark(character: card.character, size: size);
  }
}

/// Deliberately quiet: a count and a hairline bar, no question numbers shouted
/// at the user.
class _PlacementProgress extends StatelessWidget {
  const _PlacementProgress({required this.controller});

  final PlacementController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canClose = Navigator.of(context).canPop();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            28,
            canClose ? 2 : 14,
            canClose ? 8 : 28,
            10,
          ),
          child: Row(
            children: [
              Text(
                '${controller.answeredCount + 1} / ~${controller.estimatedTotal}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.mutedText,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              if (canClose)
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: controller.progress),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: theme.hairline,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlacementResults extends StatelessWidget {
  const _PlacementResults({required this.summary, required this.onFinished});

  final PlacementSummary? summary;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final known = summary?.knownCount ?? 0;
    final confirming = summary?.confirmCount ?? 0;
    final nothing = summary?.nothingToPlace ?? false;
    final headline = summary?.headline ?? '';
    final detail = summary?.detail;

    return OnboardingScaffold(
      step: 2,
      action: PrimaryButton(label: 'Start Learning', onPressed: onFinished),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const OnboardingHeadline(
              label: 'Placement complete',
              title: "You're all set!",
            ),
            SizedBox(height: height * 0.06),
            SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
              child: Column(
                children: [
                  Text(
                    nothing
                        ? 'Every kanji in the app is already in your reviews.'
                        : headline.isEmpty
                        ? 'Your starting point is ready.'
                        : headline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  if (!nothing && detail != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (known > 0) ...[
              SizedBox(height: height * 0.04),
              Text(
                "We've added the kanji you can already write to your library.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.mutedText,
                  height: 1.4,
                ),
              ),
            ],
            if (confirming > 0) ...[
              SizedBox(height: height * 0.02),
              Text(
                'Some others will come up in review so we can confirm them.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.mutedText,
                  height: 1.4,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
