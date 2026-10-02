import 'package:flutter/material.dart';

import '../../../core/models/onboarding.dart';
import '../../../core/theme/app_theme.dart';
import '../onboarding_hint_controller.dart';

/// Makes the hint state available to the learning screen.
///
/// Absent outside the app shell, and hints simply do not appear.
class OnboardingHintScope extends InheritedNotifier<OnboardingHintController> {
  const OnboardingHintScope({
    super.key,
    required OnboardingHintController super.notifier,
    required super.child,
  });

  static OnboardingHintController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<OnboardingHintScope>()
        ?.notifier;
  }
}

/// One quiet line of guidance, shown the first time its moment comes up.
///
/// Takes no space once the hint has been seen, so the session layout is the
/// same for everyone afterwards.
class OnboardingHintText extends StatelessWidget {
  const OnboardingHintText(this.hint, {super.key, this.padding});

  final OnboardingHint hint;

  /// Applied only while the hint is visible, so the layout is unchanged once
  /// it is gone.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final controller = OnboardingHintScope.maybeOf(context);
    if (controller == null || !controller.shouldShow(hint)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Text(
          _message(hint),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.mutedText,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  static String _message(OnboardingHint hint) {
    return switch (hint) {
      OnboardingHint.drawFromMemory => 'Draw the kanji from memory.',
      OnboardingHint.compareDrawing =>
        'Compare your drawing with the real kanji.',
      OnboardingHint.rateRecall =>
        'Good = you remembered it · Again = see it sooner',
    };
  }
}
