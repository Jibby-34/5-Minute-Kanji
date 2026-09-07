enum KanjiProgressStatus { notEncountered, learning, mastered }

extension KanjiProgressStatusX on KanjiProgressStatus {
  String get label => switch (this) {
    KanjiProgressStatus.notEncountered => 'Not encountered',
    KanjiProgressStatus.learning => 'Learning',
    KanjiProgressStatus.mastered => 'Mastered',
  };
}
