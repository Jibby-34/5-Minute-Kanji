/// Where the learner thinks they are, before any kanji is shown.
///
/// A starting guess for the placement model. [newUser] skips the test.
/// The other three only bias where the test looks first.
enum PlacementSelfAssessment {
  newUser,
  beginner,
  intermediate,
  expert;

  static PlacementSelfAssessment? fromName(String? name) {
    for (final assessment in PlacementSelfAssessment.values) {
      if (assessment.name == name) return assessment;
    }
    return null;
  }
}

/// One answer from the placement test. [known] is the user's own judgement
/// of the kanji on screen. A miss is evidence, not a hard cutoff.
class PlacementAnswer {
  const PlacementAnswer({required this.cardId, required this.known});

  final String cardId;
  final bool known;

  Map<String, dynamic> toJson() => {'cardId': cardId, 'known': known};

  static PlacementAnswer? fromJson(Map<String, dynamic> json) {
    final cardId = json['cardId'] as String?;
    if (cardId == null || cardId.isEmpty) return null;
    return PlacementAnswer(
      cardId: cardId,
      known: json['known'] as bool? ?? false,
    );
  }
}

/// Persisted placement-test state.
///
/// [completed] gates the first-launch flow and is never cleared again, so a
/// retake from Settings cannot bring the test back on the next launch.
/// [answers] exist only while a test is unfinished; they let a run be replayed
/// after the app is closed mid-test.
class PlacementProgress {
  const PlacementProgress({
    this.completed = false,
    this.answers = const [],
    this.selectionSeed = 0,
    this.selfAssessment,
  });

  static const empty = PlacementProgress();

  final bool completed;
  final List<PlacementAnswer> answers;

  /// Mixes question choice. 0 means a run has not been given one yet.
  final int selectionSeed;

  /// The learner's own starting guess. Null until they pick one.
  final PlacementSelfAssessment? selfAssessment;

  bool get hasStarted => answers.isNotEmpty;

  PlacementProgress copyWith({
    bool? completed,
    List<PlacementAnswer>? answers,
    int? selectionSeed,
    PlacementSelfAssessment? selfAssessment,
    bool clearSelfAssessment = false,
  }) {
    return PlacementProgress(
      completed: completed ?? this.completed,
      answers: answers ?? this.answers,
      selectionSeed: selectionSeed ?? this.selectionSeed,
      selfAssessment: clearSelfAssessment
          ? null
          : (selfAssessment ?? this.selfAssessment),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completed': completed,
      'answers': answers.map((answer) => answer.toJson()).toList(),
      'selectionSeed': selectionSeed,
      if (selfAssessment != null) 'selfAssessment': selfAssessment!.name,
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
        selectionSeed: (json['selectionSeed'] as num?)?.toInt() ?? 0,
        selfAssessment: PlacementSelfAssessment.fromName(
          json['selfAssessment'] as String?,
        ),
      );
    } catch (_) {
      return empty;
    }
  }
}

/// What the test concluded.
///
/// [knownCardIds] are marked known. [confirmCardIds] are queued for a light
/// review. Tested kanji follow the answer the learner gave; the probabilities
/// apply only to kanji the test did not show.
class PlacementOutcome {
  const PlacementOutcome({
    required this.knownCardIds,
    this.confirmCardIds = const [],
    required this.answeredCount,
    this.estimatedDifficulty = 0,
    this.intervalLow = 0,
    this.intervalHigh = 0,
    this.corpusPosition = 0,
    this.headline = '',
    this.detail,
    this.nothingToPlace = false,
  });

  static const empty = PlacementOutcome(
    knownCardIds: [],
    answeredCount: 0,
    nothingToPlace: true,
  );

  /// Kanji to hand to the existing Mark as Known path.
  final List<String> knownCardIds;

  /// Untested kanji that should come back soon for confirmation.
  final List<String> confirmCardIds;

  final int answeredCount;

  /// Posterior mean on the 1–100 difficulty scale. An estimate, not a cutoff.
  final double estimatedDifficulty;

  /// 10th and 90th percentiles of the posterior.
  final int intervalLow;
  final int intervalHigh;

  /// How many catalog kanji have difficulty at or below [estimatedDifficulty].
  final int corpusPosition;

  /// Short result line, such as "You're roughly late N3".
  final String headline;

  /// Optional note when the credible interval reaches a later level.
  final String? detail;

  /// True when there was nothing left to ask about.
  final bool nothingToPlace;
}

/// Results-screen copy data.
class PlacementSummary {
  const PlacementSummary({
    required this.knownCount,
    this.confirmCount = 0,
    this.headline = '',
    this.detail,
    this.nothingToPlace = false,
  });

  /// How many kanji this test moved into the known state.
  final int knownCount;

  /// How many untested kanji were queued for confirmation.
  final int confirmCount;

  final String headline;
  final String? detail;
  final bool nothingToPlace;
}
