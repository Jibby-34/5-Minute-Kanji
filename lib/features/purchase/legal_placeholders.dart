import 'package:flutter/material.dart';

/// Placeholder until a public Terms of Use URL exists.
///
/// App Store review needs a working terms link on the subscription screen
/// and a URL in App Store Connect. Replace this screen with that URL.
class TermsOfUsePlaceholder extends StatelessWidget {
  const TermsOfUsePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalPlaceholder(
      title: 'Terms of Use',
      body:
          'Placeholder. These terms are not published yet. '
          'Using 5-Minute Kanji means you agree to the terms that will be '
          'posted here before the app is submitted for review.',
    );
  }
}

/// Placeholder until a public Privacy Policy URL exists.
///
/// App Store Connect and Play Console both require a privacy policy URL.
/// Replace this screen with that URL.
class PrivacyPolicyPlaceholder extends StatelessWidget {
  const PrivacyPolicyPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalPlaceholder(
      title: 'Privacy Policy',
      body:
          'Placeholder. A privacy policy is not published yet. '
          '5-Minute Kanji stores study progress on this device. '
          'Purchases are handled by Apple or Google. '
          'Replace this screen with the public policy before release.',
    );
  }
}

class _LegalPlaceholder extends StatelessWidget {
  const _LegalPlaceholder({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
