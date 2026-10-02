import 'package:flutter/material.dart';

/// Centred copy that scrolls instead of overflowing when type is scaled up.
///
/// Used by the single-message screens: welcome, placement, completion.
class CenteredCopy extends StatelessWidget {
  const CenteredCopy({
    super.key,
    required this.children,
    this.horizontalPadding = 32,
  });

  final List<Widget> children;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        );
      },
    );
  }
}
