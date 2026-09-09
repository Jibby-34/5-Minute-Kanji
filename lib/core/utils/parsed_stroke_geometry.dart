import 'package:flutter/painting.dart';

import '../models/stroke_data.dart';
import 'svg_path_parser.dart';

/// Parsed vector strokes ready for animation or future path comparison.
class ParsedStrokeGeometry {
  ParsedStrokeGeometry({
    required this.data,
    required this.paths,
    required this.lengths,
  });

  final StrokeData data;
  final List<Path> paths;
  final List<double> lengths;

  int get strokeCount => paths.length;

  factory ParsedStrokeGeometry.fromStrokeData(
    StrokeData data, {
    SvgPathParser parser = const SvgPathParser(),
  }) {
    final paths = [
      for (final stroke in data.strokes) parser.parse(stroke.pathData),
    ];
    final lengths = [for (final path in paths) totalLength(path)];
    return ParsedStrokeGeometry(data: data, paths: paths, lengths: lengths);
  }

  static double totalLength(Path path) {
    var length = 0.0;
    for (final metric in path.computeMetrics()) {
      length += metric.length;
    }
    return length;
  }

  /// Progressively reveals [path] from its start, using [t] in `0…1`.
  static Path extractPartial(Path path, double t) {
    if (t <= 0) return Path();
    if (t >= 1) return Path.from(path);

    final total = totalLength(path);
    if (total <= 0) return Path();

    var remaining = total * t.clamp(0.0, 1.0);
    final result = Path();
    for (final metric in path.computeMetrics()) {
      if (remaining <= 0) break;
      final take = remaining < metric.length ? remaining : metric.length;
      result.addPath(metric.extractPath(0, take), Offset.zero);
      remaining -= take;
    }
    return result;
  }
}
