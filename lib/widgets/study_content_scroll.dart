import 'package:flutter/material.dart';

/// Pins study content to the top and scrolls only when it no longer fits.
///
/// Short phones can reach the vocabulary. Tall phones keep the same spacing
/// instead of opening a gap above the kanji.
class StudyContentScroll extends StatelessWidget {
  const StudyContentScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return child;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: child,
        );
      },
    );
  }
}
