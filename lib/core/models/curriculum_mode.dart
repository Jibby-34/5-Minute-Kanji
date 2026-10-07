/// Which order new kanji are introduced in.
///
/// This is separate from SRS scheduling. It answers which unlearned kanji
/// comes next, not when a card is due.
enum CurriculumMode {
  /// Frequency, JLPT, difficulty, and component familiarity together.
  recommended,

  /// Lower frequency rank first.
  frequency,

  /// JLPT section order, then frequency inside a level.
  jlpt,

  /// Easier kanji first, using the existing difficulty field.
  difficulty,

  /// A future user-defined order. Until one is supplied, ranking matches
  /// [recommended].
  custom;

  static const CurriculumMode defaultMode = CurriculumMode.recommended;

  /// Stored settings that are missing or unrecognized stay on [defaultMode].
  static CurriculumMode fromStorage(String? name) {
    for (final mode in CurriculumMode.values) {
      if (mode.name == name) return mode;
    }
    return defaultMode;
  }
}
