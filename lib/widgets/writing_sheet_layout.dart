import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models/handwriting.dart';
import '../features/review/widgets/handwriting_pad.dart';

/// Writing square placed the way the original screen did, with [prompt]
/// sitting just below the top.
///
/// [headerHeight] is the height of the original prompt block, including the
/// gap before the square. The square stays put when the new prompt is a
/// little larger, and only moves down if that prompt would cover it.
class WritingSheetLayout extends StatelessWidget {
  const WritingSheetLayout({
    super.key,
    required this.prompt,
    required this.drawing,
    required this.onDrawingChanged,
    required this.headerHeight,
    this.promptOffset = 12,
  });

  final Widget prompt;
  final HandwritingInput drawing;
  final ValueChanged<HandwritingInput> onDrawingChanged;

  /// Original block above the square. Anchors the square in its old position.
  final double headerHeight;

  /// How far below the top the prompt sits, compared with the original.
  final double promptOffset;

  @override
  Widget build(BuildContext context) {
    final pad = HandwritingPad(
      value: drawing,
      onChanged: onDrawingChanged,
      showClear: true,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight || !constraints.maxHeight.isFinite) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              prompt,
              const SizedBox(height: 16),
              SizedBox(width: 240, height: 240, child: pad),
            ],
          );
        }

        return CustomMultiChildLayout(
          delegate: _WritingSheetDelegate(
            headerHeight: headerHeight,
            promptOffset: promptOffset,
          ),
          children: [
            LayoutId(id: _WritingSlot.prompt, child: prompt),
            LayoutId(id: _WritingSlot.pad, child: pad),
          ],
        );
      },
    );
  }
}

enum _WritingSlot { prompt, pad }

class _WritingSheetDelegate extends MultiChildLayoutDelegate {
  _WritingSheetDelegate({
    required this.headerHeight,
    required this.promptOffset,
  });

  final double headerHeight;
  final double promptOffset;

  static const _clearance = 8.0;

  @override
  void performLayout(Size size) {
    final promptSize = layoutChild(
      _WritingSlot.prompt,
      BoxConstraints(maxWidth: size.width),
    );

    var header = headerHeight;
    var padTop = _padTop(size, header);
    if (promptOffset + promptSize.height + _clearance > padTop) {
      header = promptOffset + promptSize.height + _clearance;
      padTop = _padTop(size, header);
    }

    final side = _side(size, header);
    layoutChild(_WritingSlot.pad, BoxConstraints.tight(Size(side, side)));
    positionChild(
      _WritingSlot.prompt,
      Offset((size.width - promptSize.width) / 2, promptOffset),
    );
    positionChild(_WritingSlot.pad, Offset((size.width - side) / 2, padTop));
  }

  double _side(Size size, double header) {
    final expanded = math.max(0.0, size.height - header);
    return math.min(size.width, expanded);
  }

  /// Same placement as the old column: the square is centered in whatever
  /// space is left under [header].
  double _padTop(Size size, double header) {
    final expanded = math.max(0.0, size.height - header);
    final side = math.min(size.width, expanded);
    return header + (expanded - side) / 2;
  }

  @override
  bool shouldRelayout(covariant _WritingSheetDelegate oldDelegate) {
    return oldDelegate.headerHeight != headerHeight ||
        oldDelegate.promptOffset != promptOffset;
  }
}
