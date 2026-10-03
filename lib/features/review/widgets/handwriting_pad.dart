import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/models/handwriting.dart';
import '../../../core/theme/app_theme.dart';

class HandwritingPad extends StatefulWidget {
  const HandwritingPad({
    super.key,
    required this.value,
    this.onChanged,
    this.readOnly = false,
    this.showClear = false,
  });

  final HandwritingInput value;
  final ValueChanged<HandwritingInput>? onChanged;
  final bool readOnly;
  final bool showClear;

  @override
  State<HandwritingPad> createState() => _HandwritingPadState();
}

class _HandwritingPadState extends State<HandwritingPad> {
  late HandwritingInput _input;
  HandwritingStroke? _active;
  int? _pointer;

  @override
  void initState() {
    super.initState();
    _input = widget.value;
  }

  @override
  void didUpdateWidget(HandwritingPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value) && _active == null) {
      _input = widget.value;
    }
  }

  bool _accepts(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.mouse;
  }

  StrokePoint _normalize(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return const StrokePoint(0, 0);
    }
    return StrokePoint(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  void _emit(HandwritingInput next) {
    _input = next;
    widget.onChanged?.call(next);
  }

  void _start(Offset local, Size size) {
    _active = HandwritingStroke([_normalize(local, size)]);
    setState(() {
      _emit(_input.copyWith(strokes: [..._input.strokes, _active!]));
    });
  }

  void _update(Offset local, Size size) {
    if (_active == null) return;
    final nextActive = HandwritingStroke([
      ..._active!.points,
      _normalize(local, size),
    ]);
    _active = nextActive;
    final strokes = [..._input.strokes];
    if (strokes.isEmpty) return;
    strokes[strokes.length - 1] = nextActive;
    setState(() => _emit(_input.copyWith(strokes: strokes)));
  }

  void _end() {
    _active = null;
    _pointer = null;
  }

  void _clear() {
    if (widget.readOnly) return;
    _active = null;
    _pointer = null;
    setState(() => _emit(HandwritingInput.empty));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final grid = theme.hairline;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardWash,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: grid),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: widget.readOnly
                      ? null
                      : (event) {
                          if (!_accepts(event.kind) || _pointer != null) {
                            return;
                          }
                          _pointer = event.pointer;
                          _start(event.localPosition, size);
                        },
                  onPointerMove: widget.readOnly
                      ? null
                      : (event) {
                          if (event.pointer != _pointer) return;
                          _update(event.localPosition, size);
                        },
                  onPointerUp: widget.readOnly
                      ? null
                      : (event) {
                          if (event.pointer != _pointer) return;
                          _end();
                        },
                  onPointerCancel: widget.readOnly
                      ? null
                      : (event) {
                          if (event.pointer != _pointer) return;
                          _end();
                        },
                  child: CustomPaint(
                    painter: _HandwritingPainter(
                      input: _input,
                      ink: ink,
                      grid: grid,
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.showClear && !widget.readOnly)
            Positioned(
              top: 4,
              right: 4,
              child: TextButton(
                onPressed: _input.isEmpty ? null : _clear,
                style: TextButton.styleFrom(
                  foregroundColor: theme.mutedText,
                  minimumSize: const Size(48, 40),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Clear'),
              ),
            ),
        ],
      ),
    );
  }
}

class _HandwritingPainter extends CustomPainter {
  _HandwritingPainter({
    required this.input,
    required this.ink,
    required this.grid,
  });

  final HandwritingInput input;
  final Color ink;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    // Dashed centre guides, the way a practice square is ruled on paper.
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.85)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    _dashedLine(
      canvas,
      Offset(size.width / 2, 8),
      Offset(size.width / 2, size.height - 8),
      gridPaint,
    );
    _dashedLine(
      canvas,
      Offset(8, size.height / 2),
      Offset(size.width - 8, size.height / 2),
      gridPaint,
    );

    final inkPaint = Paint()
      ..color = ink
      ..strokeWidth = (size.shortestSide * 0.028).clamp(2.5, 5.5)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in input.strokes) {
      _paintStroke(canvas, size, stroke, inkPaint);
    }
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 5.0;
    const gap = 5.0;
    final span = to - from;
    final length = span.distance;
    if (length <= 0) return;
    final step = span / length;

    for (var travelled = 0.0; travelled < length; travelled += dash + gap) {
      final end = math.min(travelled + dash, length);
      canvas.drawLine(from + step * travelled, from + step * end, paint);
    }
  }

  void _paintStroke(
    Canvas canvas,
    Size size,
    HandwritingStroke stroke,
    Paint paint,
  ) {
    if (stroke.points.isEmpty) return;
    Offset toOffset(StrokePoint point) =>
        Offset(point.x * size.width, point.y * size.height);

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        toOffset(stroke.points.first),
        paint.strokeWidth / 2,
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path()
      ..moveTo(
        toOffset(stroke.points.first).dx,
        toOffset(stroke.points.first).dy,
      );
    for (var i = 1; i < stroke.points.length; i++) {
      final previous = toOffset(stroke.points[i - 1]);
      final current = toOffset(stroke.points[i]);
      final mid = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    path.lineTo(
      toOffset(stroke.points.last).dx,
      toOffset(stroke.points.last).dy,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HandwritingPainter oldDelegate) {
    return oldDelegate.input != input ||
        oldDelegate.ink != ink ||
        oldDelegate.grid != grid;
  }
}
