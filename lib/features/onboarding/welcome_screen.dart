import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import 'widgets/onboarding_scaffold.dart';

/// First screen. Says that study is shaped around a few minutes, with an
/// example of what that can look like.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  static const title = 'Kanji study that fits your day.';
  static const subtitle =
      "Make the most of your time. We'll prioritize your reviews to fit the time you have.";

  /// Space between the example card and the headline.
  static const double _cardGap = 20;

  /// Space between the headline and the supporting line.
  static const double _titleGap = 16;

  static TextStyle _titleStyle(ThemeData theme) {
    return (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontSize: 38,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
      height: 1.1,
    );
  }

  static TextStyle _subtitleStyle(ThemeData theme) {
    return (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: theme.mutedText,
      fontSize: 17,
      fontWeight: FontWeight.w500,
      height: 1.45,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = _titleStyle(theme);
    final subtitleStyle = _subtitleStyle(theme);

    return OnboardingScaffold(
      step: 1,
      action: PrimaryButton(label: 'Get Started', onPressed: onGetStarted),
      content: (context, _) {
        // The scaffold gives this column the space between the dots and the
        // button, and scrolls it only when the column is taller than that.
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PlanCard(),
            const SizedBox(height: _cardGap),
            Text(title, textAlign: TextAlign.center, style: titleStyle),
            const SizedBox(height: _titleGap),
            Text(subtitle, textAlign: TextAlign.center, style: subtitleStyle),
          ],
        );
      },
    );
  }
}

/// Example split for one five-minute sitting. The times are a picture, not
/// a live plan.
class _PlanCard extends StatelessWidget {
  const _PlanCard();

  static const _semanticsLabel =
      'Example plan: 5 minutes. Priority reviews 3 minutes 10 seconds. New kanji 1 minute 50 seconds.';

  static const _heading = 'YOUR 5-MINUTE PLAN';
  static const _caption = 'Example plan';
  static const _total = '5 min';

  static const _reviewsLabel = 'Priority reviews';
  static const _reviewsTime = '3 min 10 sec';
  static const _newKanjiLabel = 'New kanji';
  static const _newKanjiTime = '1 min 50 sec';

  /// A step lighter than the paper scaffold. No theme token for that.
  static const _fill = Color(0xFFFBF9F5);

  /// "New kanji" share of the example. No theme token for this indigo.
  static const _newKanjiInk = Color(0xFF8E96C4);

  static const _reviewsShare = 190;
  static const _newKanjiShare = 110;

  static TextStyle _headingStyle(ThemeData theme) {
    return (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: theme.mutedText,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
      height: 1.2,
    );
  }

  static TextStyle _captionStyle(ThemeData theme) {
    return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: theme.mutedText,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );
  }

  static TextStyle _totalStyle(ThemeData theme) {
    return (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.primary,
      fontSize: 34,
      fontWeight: FontWeight.w700,
      height: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navy = theme.colorScheme.primary;

    return Semantics(
      container: true,
      label: _semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: theme.hairline, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: navy.withValues(alpha: 0.08),
                offset: const Offset(0, 2),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _heading,
                textAlign: TextAlign.center,
                style: _headingStyle(theme),
              ),
              const SizedBox(height: 4),
              Text(
                _caption,
                textAlign: TextAlign.center,
                style: _captionStyle(theme),
              ),
              const SizedBox(height: 10),
              Text(
                _total,
                textAlign: TextAlign.center,
                style: _totalStyle(theme),
              ),
              const SizedBox(height: 18),
              _ProportionBar(
                reviews: navy,
                newKanji: _newKanjiInk,
                reviewsShare: _reviewsShare,
                newKanjiShare: _newKanjiShare,
              ),
              const SizedBox(height: 20),
              _PlanRow(color: navy, label: _reviewsLabel, time: _reviewsTime),
              const SizedBox(height: 14),
              const _PlanRow(
                color: _newKanjiInk,
                label: _newKanjiLabel,
                time: _newKanjiTime,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.color,
    required this.label,
    required this.time,
  });

  final Color color;
  final String label;
  final String time;

  static TextStyle _labelStyle(ThemeData theme) {
    return (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  static TextStyle _timeStyle(ThemeData theme) {
    return (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Row(
            children: [
              _ShareDot(color: color),
              const SizedBox(width: 8),
              Flexible(child: Text(label, style: _labelStyle(theme))),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(time, style: _timeStyle(theme)),
      ],
    );
  }
}

class _ShareDot extends StatelessWidget {
  const _ShareDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// Decorative split of the example five minutes. Not a progress indicator.
class _ProportionBar extends StatelessWidget {
  const _ProportionBar({
    required this.reviews,
    required this.newKanji,
    required this.reviewsShare,
    required this.newKanjiShare,
  });

  final Color reviews;
  final Color newKanji;
  final int reviewsShare;
  final int newKanjiShare;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: reviewsShare,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: reviews,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              flex: newKanjiShare,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: newKanji,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
