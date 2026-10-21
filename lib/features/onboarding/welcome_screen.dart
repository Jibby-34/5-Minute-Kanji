import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/kanji_mark.dart';
import '../../widgets/primary_button.dart';
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
              child: KanjiMark(character: '字', size: glyph, halo: false),
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
            const SizedBox(height: 16),
            Text(
              "A few minutes a day is all it takes. We'll track what to review.",
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.mutedText,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
        );
      },
    );
  }
}
