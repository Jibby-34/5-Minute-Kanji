import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/bottom_action_inset.dart';
import '../../../widgets/section_label.dart';

/// Number of set-up steps the dots represent: welcome, placement, daily goal.
/// The screens after the first session are a result and an ask, not set-up,
/// so they carry no progress.
const int onboardingSetupSteps = 3;

/// Builds the middle zone. [height] is the space the zone has to work with,
/// so screens can scale a hero element instead of guessing.
typedef OnboardingContentBuilder =
    Widget Function(BuildContext context, double height);

/// Shared frame for every onboarding screen: a light header, one main idea in
/// the middle, and the action pinned above the home indicator.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.content,
    required this.action,
    this.step,
    this.header,
    this.horizontalPadding = 28,
  });

  /// Middle zone.
  final OnboardingContentBuilder content;

  /// Bottom zone. Usually a [PrimaryButton] or a pair of actions.
  final Widget action;

  /// 1-based set-up step, when the screen is part of the set-up sequence.
  final int? step;

  /// Replaces the default progress row, for screens with their own header.
  final Widget? header;

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    // Screens without a header keep the same top space, so the middle zone
    // starts at the same height throughout the flow.
    final head =
        header ??
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            14,
            horizontalPadding,
            0,
          ),
          child: SizedBox(
            height: 28,
            child: Center(
              child: step == null ? null : OnboardingProgress(step!),
            ),
          ),
        );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            head,
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 8,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 16,
                      ),
                      child: content(context, constraints.maxHeight - 16),
                    ),
                  );
                },
              ),
            ),
            BottomActionInset(
              horizontalPadding: horizontalPadding,
              child: action,
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet dot sequence: filled for finished and current steps.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress(
    this.step, {
    super.key,
    this.total = onboardingSetupSteps,
  });

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Step $step of $total',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 1; index <= total; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index <= step
                      ? theme.colorScheme.primary
                      : theme.hairline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Title, with optional caps label above and supporting line below.
class OnboardingHeadline extends StatelessWidget {
  const OnboardingHeadline({
    super.key,
    required this.title,
    this.label,
    this.subtitle,
    this.align = TextAlign.center,
  });

  final String title;
  final String? label;
  final String? subtitle;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cross = align == TextAlign.center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: cross,
      children: [
        if (label != null) ...[
          SectionLabel(label!, align: align),
          const SizedBox(height: 12),
        ],
        Text(
          title,
          textAlign: align,
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
            height: 1.15,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          Text(
            subtitle!,
            textAlign: align,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.mutedText,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

/// A number worth reading from across the room, with its unit underneath.
class OnboardingStat extends StatelessWidget {
  const OnboardingStat({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -1.5,
            height: 1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
