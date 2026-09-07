class StrokePoint {
  const StrokePoint(this.x, this.y);

  /// Horizontal position in the pad, 0–1.
  final double x;

  /// Vertical position in the pad, 0–1.
  final double y;
}

class HandwritingStroke {
  const HandwritingStroke(this.points);

  final List<StrokePoint> points;

  bool get isEmpty => points.isEmpty;
}

class HandwritingInput {
  const HandwritingInput({this.strokes = const []});

  static const empty = HandwritingInput();

  final List<HandwritingStroke> strokes;

  bool get isEmpty => strokes.every((stroke) => stroke.isEmpty);

  HandwritingInput copyWith({List<HandwritingStroke>? strokes}) {
    return HandwritingInput(strokes: strokes ?? this.strokes);
  }
}

class ReviewAnswer {
  const ReviewAnswer({
    required this.cardId,
    required this.drawing,
    required this.submittedAt,
  });

  final String cardId;
  final HandwritingInput drawing;
  final DateTime submittedAt;
}
