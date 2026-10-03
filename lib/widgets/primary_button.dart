import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Full-width primary action. Metrics come from the theme so primary and
/// secondary actions always match.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = AppTheme.buttonHeight,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton(onPressed: onPressed, child: Text(label)),
    );
  }
}

/// Full-width alternative action. Same shape and weight as [PrimaryButton],
/// quieter colour.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = AppTheme.buttonHeight,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(onPressed: onPressed, child: Text(label)),
    );
  }
}

/// One half of the recall answer pair. [isPrimary] marks the button that
/// carries the session forward.
class RatingButton extends StatelessWidget {
  const RatingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: isPrimary
            ? PrimaryButton(label: label, onPressed: onPressed)
            : SecondaryButton(label: label, onPressed: onPressed),
      ),
    );
  }
}
