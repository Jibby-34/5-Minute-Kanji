import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// One ordered vector stroke from KanjiVG, preserved for animation and
/// future handwriting guidance/grading.
class KanjiStroke {
  const KanjiStroke({required this.pathData, this.numberPosition});

  /// SVG path `d` data in the source viewBox coordinate space.
  final String pathData;

  /// Optional KanjiVG stroke-number label position in viewBox coordinates.
  final Offset? numberPosition;

  factory KanjiStroke.fromJson(Map<String, dynamic> json) {
    final number = json['number'];
    Offset? position;
    if (number is List && number.length >= 2) {
      position = Offset(
        (number[0] as num).toDouble(),
        (number[1] as num).toDouble(),
      );
    }
    return KanjiStroke(
      pathData: json['d'] as String? ?? '',
      numberPosition: position,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'd': pathData,
      if (numberPosition != null)
        'number': [numberPosition!.dx, numberPosition!.dy],
    };
  }

  @override
  bool operator ==(Object other) {
    return other is KanjiStroke &&
        other.pathData == pathData &&
        other.numberPosition == numberPosition;
  }

  @override
  int get hashCode => Object.hash(pathData, numberPosition);
}

/// Ordered stroke-order geometry for a single kanji character.
class StrokeData {
  const StrokeData({
    required this.character,
    required this.unicodeHex,
    required this.viewBox,
    required this.strokes,
  });

  final String character;
  final String unicodeHex;
  final Rect viewBox;
  final List<KanjiStroke> strokes;

  int get strokeCount => strokes.length;

  factory StrokeData.fromJson(Map<String, dynamic> json) {
    final box = json['viewBox'];
    var viewBox = const Rect.fromLTWH(0, 0, 109, 109);
    if (box is List && box.length >= 4) {
      viewBox = Rect.fromLTWH(
        (box[0] as num).toDouble(),
        (box[1] as num).toDouble(),
        (box[2] as num).toDouble(),
        (box[3] as num).toDouble(),
      );
    }

    final rawStrokes = json['strokes'];
    final strokes = <KanjiStroke>[
      if (rawStrokes is List)
        for (final stroke in rawStrokes)
          if (stroke is Map)
            KanjiStroke.fromJson(Map<String, dynamic>.from(stroke)),
    ];

    return StrokeData(
      character: json['character'] as String? ?? '',
      unicodeHex: json['unicode'] as String? ?? '',
      viewBox: viewBox,
      strokes: strokes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'character': character,
      'unicode': unicodeHex,
      'viewBox': [viewBox.left, viewBox.top, viewBox.width, viewBox.height],
      'strokes': [for (final stroke in strokes) stroke.toJson()],
    };
  }

  @override
  bool operator ==(Object other) {
    return other is StrokeData &&
        other.character == character &&
        other.unicodeHex == unicodeHex &&
        other.viewBox == viewBox &&
        listEquals(other.strokes, strokes);
  }

  @override
  int get hashCode => Object.hash(character, unicodeHex, viewBox, strokeCount);
}
