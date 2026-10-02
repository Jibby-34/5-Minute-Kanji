/// How far the first-launch experience has progressed.
///
/// Ordered: a stage is only ever replaced by a later one, so reopening the app
/// mid-onboarding resumes instead of starting over.
enum OnboardingStage {
  notStarted,
  placementInProgress,
  placementCompleted,
  dailyGoalSelected,
  firstSessionCompleted,
  completed;

  static OnboardingStage fromName(String? name) {
    return OnboardingStage.values.firstWhere(
      (stage) => stage.name == name,
      orElse: () => OnboardingStage.notStarted,
    );
  }

  bool isAtLeast(OnboardingStage other) => index >= other.index;
}

/// One-time pointers shown inside the real learning screen.
///
/// Each is tied to the first time its moment happens, not to the onboarding
/// route, so a user who closes the app before their first session still sees
/// them when they get there.
enum OnboardingHint {
  /// The recall phase: an empty pad with only the keyword.
  drawFromMemory,

  /// The compare phase: their drawing next to the real kanji.
  compareDrawing,

  /// The Again / Good choice.
  rateRecall;

  static OnboardingHint? fromName(String? name) {
    for (final hint in OnboardingHint.values) {
      if (hint.name == name) return hint;
    }
    return null;
  }
}

/// Persisted onboarding state. Lives in the app's existing progress store.
class OnboardingProgress {
  const OnboardingProgress({
    this.stage = OnboardingStage.notStarted,
    this.seenHints = const {},
  });

  static const empty = OnboardingProgress();

  final OnboardingStage stage;
  final Set<OnboardingHint> seenHints;

  bool get isComplete => stage == OnboardingStage.completed;

  bool hasSeen(OnboardingHint hint) => seenHints.contains(hint);

  OnboardingProgress copyWith({
    OnboardingStage? stage,
    Set<OnboardingHint>? seenHints,
  }) {
    return OnboardingProgress(
      stage: stage ?? this.stage,
      seenHints: seenHints ?? this.seenHints,
    );
  }

  /// Moves forward to [next], never backwards.
  OnboardingProgress atLeast(OnboardingStage next) {
    return stage.isAtLeast(next) ? this : copyWith(stage: next);
  }

  OnboardingProgress withHintSeen(OnboardingHint hint) {
    if (hasSeen(hint)) return this;
    return copyWith(seenHints: {...seenHints, hint});
  }

  Map<String, dynamic> toJson() {
    return {
      'stage': stage.name,
      'seenHints': [for (final hint in seenHints) hint.name],
    };
  }

  static OnboardingProgress fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    try {
      final rawHints = json['seenHints'];
      final hints = <OnboardingHint>{};
      if (rawHints is List) {
        for (final item in rawHints) {
          final hint = OnboardingHint.fromName(item?.toString());
          if (hint != null) hints.add(hint);
        }
      }
      return OnboardingProgress(
        stage: OnboardingStage.fromName(json['stage'] as String?),
        seenHints: hints,
      );
    } catch (_) {
      return empty;
    }
  }
}
