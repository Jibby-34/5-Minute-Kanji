import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Small tracked caps used to name a block of content without competing
/// with it.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key, this.align = TextAlign.start});

  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      label.toUpperCase(),
      textAlign: align,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.mutedText,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        height: 1.2,
      ),
    );
  }
}

/// Short centered rule. A quiet stationery mark between a visual and the
/// text that explains it.
class HairlineMark extends StatelessWidget {
  const HairlineMark({super.key, this.width = 44});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 1,
      color: Theme.of(context).hairline,
    );
  }
}
