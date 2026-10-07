import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/kanji_mark.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import 'widgets/onboarding_scaffold.dart';

/// First thing a new user sees. Says what the app is in one line and gets out
/// of the way.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OnboardingScaffold(
      step: 1,
      action: PrimaryButton(label: 'Get Started', onPressed: onGetStarted),
      content: (context, height) {
        final glyph = (height * 0.26).clamp(84.0, 168.0);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 字 — the character in "kanji". Stands in for the whole app.
            ExcludeSemantics(
              child: KanjiMark(character: '字', size: glyph),
            ),
            SizedBox(height: height * 0.06),
            Text(
              '5-Minute Kanji',
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 20),
            const HairlineMark(),
            const SizedBox(height: 20),
            Text(
              'Learn kanji in 5 minutes a day.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 21,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Short sessions. Spaced repetition.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
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
