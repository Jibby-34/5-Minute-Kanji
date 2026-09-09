import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/parsed_stroke_geometry.dart';
import '../../repositories/stroke_data_repository.dart';
import 'stroke_order_timeline.dart';

class KanjiStrokeAnimation extends StatefulWidget {
  const KanjiStrokeAnimation({
    super.key,
    required this.character,
    this.autoPlay = true,
    this.startCompleted = false,
    this.size = 196,
    this.showReplay = true,
    this.showStrokeCount = false,
    this.showStrokeNumbers = true,
    this.showFrame = true,
    this.showFallbackCharacter = false,
    this.replayColor,
  });

  final String character;
  final bool autoPlay;

  /// When true and [autoPlay] is false, the finished glyph is shown at rest.
  final bool startCompleted;
  final double size;
  final bool showReplay;
  final bool showStrokeCount;
  final bool showStrokeNumbers;

  /// When false, the glyph sits directly on the page with no grid or card.
  final bool showFrame;

  /// Learn uses this so a missing asset still shows the character.
  final bool showFallbackCharacter;

  /// Overrides the replay control color. Defaults to accent in a frame,
  /// muted text when unframed.
  final Color? replayColor;

  @override
  State<KanjiStrokeAnimation> createState() => KanjiStrokeAnimationState();
}

class KanjiStrokeAnimationState extends State<KanjiStrokeAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ParsedStrokeGeometry? _geometry;
  StrokeOrderTimeline? _timeline;
  var _loaded = false;
  var _missing = false;
  var _loadStarted = false;

  bool get isPlaying => _controller.isAnimating;

  bool get hasStrokeData => _geometry != null;

  bool get isComplete => _controller.value >= 1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(KanjiStrokeAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character != widget.character) {
      _controller.stop();
      _controller.value = 0;
      _geometry = null;
      _timeline = null;
      _loaded = false;
      _missing = false;
      _loadStarted = true;
      _load();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    StrokeDataRepository? repo;
    try {
      repo = Provider.of<StrokeDataRepository>(context, listen: false);
    } on ProviderNotFoundException {
      repo = null;
    }
    if (repo == null) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _missing = true;
      });
      return;
    }

    final data = await repo.getForCharacter(widget.character);
    if (!mounted) return;
    if (data == null || data.strokes.isEmpty) {
      setState(() {
        _loaded = true;
        _missing = true;
        _geometry = null;
        _timeline = null;
      });
      return;
    }

    final geometry = ParsedStrokeGeometry.fromStrokeData(data);
    final timeline = StrokeOrderTimeline.from(geometry);
    _controller.duration = timeline.total;
    setState(() {
      _geometry = geometry;
      _timeline = timeline;
      _loaded = true;
      _missing = false;
    });
    if (!mounted) return;
    if (widget.autoPlay) {
      await _controller.forward(from: 0);
    } else if (widget.startCompleted) {
      _controller.value = 1;
    }
  }

  void play() {
    if (_geometry == null) return;
    _controller.forward();
  }

  void pause() {
    _controller.stop();
    setState(() {});
  }

  void resume() {
    if (_geometry == null) return;
    if (_controller.value >= 1) return;
    _controller.forward();
  }

  void restart() {
    if (_geometry == null) return;
    _controller.forward(from: 0);
  }

  void _onCanvasTap() {
    if (_geometry == null) return;
    if (_controller.isAnimating) {
      pause();
    } else if (_controller.value > 0 && _controller.value < 1) {
      resume();
    } else {
      restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(
          widget.size,
          constraints.maxWidth.isFinite ? constraints.maxWidth : widget.size,
        );
        final theme = Theme.of(context);

        if (!_loaded) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: SizedBox(width: side, height: side),
              ),
            ],
          );
        }

        if (_missing || _geometry == null || _timeline == null) {
          if (!widget.showFallbackCharacter) {
            return const SizedBox.shrink();
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [Center(child: _fallbackGlyph(theme, side))],
          );
        }

        final snapshot = _timeline!.at(_controller.value);
        final geometry = _geometry!;
        final canvas = Semantics(
          label: '${widget.character}, stroke order',
          button: true,
          hint: 'Replay the stroke order animation',
          onTap: _onCanvasTap,
          child: GestureDetector(
            onTap: _onCanvasTap,
            behavior: HitTestBehavior.opaque,
            child: widget.showFrame
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? AppColors.darkSurface
                          : AppColors.paperDeep.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.hairline),
                    ),
                    child: _paint(theme, geometry, snapshot),
                  )
                : _paint(theme, geometry, snapshot),
          ),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: SizedBox(width: side, height: side, child: canvas),
            ),
            if (widget.showStrokeCount) ...[
              const SizedBox(height: 10),
              Text(
                '${geometry.strokeCount} ${geometry.strokeCount == 1 ? 'stroke' : 'strokes'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.mutedText,
                ),
              ),
            ],
            if (widget.showReplay) _replayButton(theme),
          ],
        );
      },
    );
  }

  Widget _paint(
    ThemeData theme,
    ParsedStrokeGeometry geometry,
    StrokeAnimationSnapshot snapshot,
  ) {
    return CustomPaint(
      painter: KanjiStrokePainter(
        geometry: geometry,
        snapshot: snapshot,
        ink: theme.colorScheme.onSurface,
        grid: theme.hairline,
        numberColor: theme.mutedText,
        showStrokeNumbers: widget.showStrokeNumbers,
        showGrid: widget.showFrame,
        strokeWidth: widget.showFrame ? 3 : 3.8,
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _fallbackGlyph(ThemeData theme, double side) {
    return Semantics(
      label: widget.character,
      child: SizedBox(
        width: side,
        height: side,
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text(
            widget.character,
            style: AppTypography.kanji(
              color: theme.colorScheme.onSurface,
              size: side,
            ),
          ),
        ),
      ),
    );
  }

  Widget _replayButton(ThemeData theme) {
    return Tooltip(
      message: 'Replay stroke order',
      child: TextButton.icon(
        onPressed: restart,
        icon: const Icon(Icons.replay, size: 16),
        label: const Text('Stroke Order'),
        style: TextButton.styleFrom(
          foregroundColor:
              widget.replayColor ??
              (widget.showFrame ? theme.colorScheme.primary : theme.mutedText),
          minimumSize: const Size(48, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class KanjiStrokePainter extends CustomPainter {
  KanjiStrokePainter({
    required this.geometry,
    required this.snapshot,
    required this.ink,
    required this.grid,
    required this.numberColor,
    required this.showStrokeNumbers,
    this.showGrid = true,
    this.strokeWidth = 3,
  });

  final ParsedStrokeGeometry geometry;
  final StrokeAnimationSnapshot snapshot;
  final Color ink;
  final Color grid;
  final Color numberColor;
  final bool showStrokeNumbers;
  final bool showGrid;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      final gridPaint = Paint()
        ..color = grid.withValues(alpha: 0.7)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        gridPaint,
      );
    }

    final viewBox = geometry.data.viewBox;
    final scale = size.shortestSide / math.max(viewBox.width, viewBox.height);
    canvas.save();
    canvas.translate(
      (size.width - viewBox.width * scale) / 2 - viewBox.left * scale,
      (size.height - viewBox.height * scale) / 2 - viewBox.top * scale,
    );
    canvas.scale(scale);

    final inkPaint = Paint()
      ..color = ink
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < snapshot.completedCount; i++) {
      canvas.drawPath(geometry.paths[i], inkPaint);
    }

    if (snapshot.activeIndex != null) {
      final partial = ParsedStrokeGeometry.extractPartial(
        geometry.paths[snapshot.activeIndex!],
        snapshot.activeProgress,
      );
      canvas.drawPath(partial, inkPaint);
    }

    if (showStrokeNumbers &&
        snapshot.numberIndex != null &&
        snapshot.numberIndex! < geometry.data.strokes.length) {
      final stroke = geometry.data.strokes[snapshot.numberIndex!];
      final position = stroke.numberPosition;
      if (position != null) {
        final label = '${snapshot.numberIndex! + 1}';
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: numberColor,
              fontSize: 8,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          Offset(position.dx - painter.width / 2, position.dy - painter.height),
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KanjiStrokePainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.snapshot != snapshot ||
        oldDelegate.ink != ink ||
        oldDelegate.grid != grid ||
        oldDelegate.numberColor != numberColor ||
        oldDelegate.showStrokeNumbers != showStrokeNumbers ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
