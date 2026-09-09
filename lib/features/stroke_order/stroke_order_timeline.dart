import '../../core/utils/parsed_stroke_geometry.dart';

class StrokeAnimationSnapshot {
  const StrokeAnimationSnapshot({
    required this.completedCount,
    this.activeIndex,
    this.activeProgress = 0,
    this.numberIndex,
  });

  final int completedCount;
  final int? activeIndex;
  final double activeProgress;
  final int? numberIndex;

  @override
  bool operator ==(Object other) {
    return other is StrokeAnimationSnapshot &&
        other.completedCount == completedCount &&
        other.activeIndex == activeIndex &&
        other.activeProgress == activeProgress &&
        other.numberIndex == numberIndex;
  }

  @override
  int get hashCode =>
      Object.hash(completedCount, activeIndex, activeProgress, numberIndex);
}

class StrokeOrderTimeline {
  const StrokeOrderTimeline({
    required this.strokeDurations,
    required this.pause,
    required this.hold,
  });

  final List<Duration> strokeDurations;
  final Duration pause;
  final Duration hold;

  factory StrokeOrderTimeline.from(ParsedStrokeGeometry geometry) {
    final lengths = geometry.lengths;
    final sorted = [...lengths]..sort();
    final median = sorted.isEmpty
        ? 1.0
        : sorted[sorted.length ~/ 2].clamp(1.0, double.infinity);
    final busy = lengths.length > 10 ? 0.78 : 1.0;

    Duration durationFor(double length) {
      final ratio = (length / median).clamp(0.7, 1.55);
      final ms = (230 * ratio * busy).clamp(160.0, 340.0);
      return Duration(milliseconds: ms.round());
    }

    return StrokeOrderTimeline(
      strokeDurations: [for (final length in lengths) durationFor(length)],
      pause: Duration(milliseconds: lengths.length > 10 ? 80 : 120),
      hold: const Duration(milliseconds: 420),
    );
  }

  Duration get total {
    var sum = Duration.zero;
    for (var i = 0; i < strokeDurations.length; i++) {
      sum += strokeDurations[i];
      if (i < strokeDurations.length - 1) {
        sum += pause;
      }
    }
    return sum + hold;
  }

  StrokeAnimationSnapshot at(double t) {
    if (strokeDurations.isEmpty) {
      return const StrokeAnimationSnapshot(completedCount: 0);
    }
    final elapsed = total.inMilliseconds * t.clamp(0.0, 1.0);
    var cursor = 0.0;
    for (var i = 0; i < strokeDurations.length; i++) {
      final drawMs = strokeDurations[i].inMilliseconds.toDouble();
      if (elapsed < cursor + drawMs) {
        final progress = drawMs == 0 ? 1.0 : (elapsed - cursor) / drawMs;
        return StrokeAnimationSnapshot(
          completedCount: i,
          activeIndex: i,
          activeProgress: progress.clamp(0.0, 1.0),
          numberIndex: i,
        );
      }
      cursor += drawMs;
      if (i < strokeDurations.length - 1) {
        if (elapsed < cursor + pause.inMilliseconds) {
          return StrokeAnimationSnapshot(completedCount: i + 1);
        }
        cursor += pause.inMilliseconds;
      }
    }
    return StrokeAnimationSnapshot(completedCount: strokeDurations.length);
  }
}
