import 'kanji_card.dart';

/// One answer from the placement test. [known] is the user's own judgement,
/// not a graded result: the test asks for recognition, not production.
class PlacementAnswer {
  const PlacementAnswer({required this.cardId, required this.known});

  final String cardId;
  final bool known;

  Map<String, dynamic> toJson() => {'cardId': cardId, 'known': known};

  static PlacementAnswer? fromJson(Map<String, dynamic> json) {
    final cardId = json['cardId'] as String?;
    if (cardId == null || cardId.isEmpty) return null;
    return PlacementAnswer(cardId: cardId, known: json['known'] as bool? ?? false);
  }
}

/// Persisted placement-test state.
///
/// [completed] gates the first-launch flow and is never cleared again, so a
/// retake from Settings cannot bring the test back on the next launch.
/// [answers] exist only while a test is unfinished; they let a run be replayed
/// after the app is closed mid-test.
class PlacementProgress {
  const PlacementProgress({this.completed = false, this.answers = const []});

  static const empty = PlacementProgress();

  final bool completed;
  final List<PlacementAnswer> answers;

  bool get hasStarted => answers.isNotEmpty;

  PlacementProgress copyWith({bool? completed, List<PlacementAnswer>? answers}) {
    return PlacementProgress(
      completed: completed ?? this.completed,
      answers: answers ?? this.answers,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completed': completed,
      'answers': answers.map((answer) => answer.toJson()).toList(),
    };
  }

  static PlacementProgress fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    try {
      final rawAnswers = json['answers'];
      final answers = <PlacementAnswer>[];
      if (rawAnswers is List) {
        for (final item in rawAnswers) {
          if (item is! Map) continue;
          final answer = PlacementAnswer.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          if (answer != null) answers.add(answer);
        }
      }
      return PlacementProgress(
        completed: json['completed'] as bool? ?? false,
        answers: answers,
      );
    } catch (_) {
      return empty;
    }
  }
}

/// What the test concluded: which kanji to treat as known, and where learning
/// should begin.
class PlacementOutcome {
  const PlacementOutcome({
    required this.knownCardIds,
    required this.answeredCount,
    this.startingLevel,
  });

  static const empty = PlacementOutcome(knownCardIds: [], answeredCount: 0);

  /// Kanji to hand to the existing Mark as Known path.
  final List<String> knownCardIds;

  final int answeredCount;

  /// JLPT level of the first kanji the user will be taught. Null when the test
  /// found nothing left to learn.
  final JlptLevel? startingLevel;
}

/// Results-screen copy data.
class PlacementSummary {
  const PlacementSummary({required this.knownCount, this.startingLevel});

  /// How many kanji this test moved into the known state.
  final int knownCount;

  final JlptLevel? startingLevel;
}
