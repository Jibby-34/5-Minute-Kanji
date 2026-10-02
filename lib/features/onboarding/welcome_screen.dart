import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/centered_copy.dart';
import '../../widgets/primary_button.dart';

/// First thing a new user sees. Says what the app is in one line and gets out
/// of the way.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: CenteredCopy(
                children: [
                  Text(
                    '5-Minute Kanji',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Learn kanji in 5 minutes a day.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Short sessions. Spaced repetition. '
                    'Actually write the kanji.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.mutedText,
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            BottomActionInset(
              child: PrimaryButton(
                label: 'Get Started',
                onPressed: onGetStarted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
