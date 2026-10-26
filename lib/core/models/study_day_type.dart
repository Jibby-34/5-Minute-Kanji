/// Which kind of study day a daily plan was built for.
///
/// Chosen once, when the plan is created, and stored with that plan.
enum StudyDayType {
  /// Reviews and new kanji, within the usual daily allowance.
  normal,

  /// Reviews only. New kanji wait until a later plan.
  reinforcement;

  static const reinforcementNote =
      'Today is about strengthening what you know.';

  String get label => switch (this) {
    StudyDayType.normal => 'Normal Day',
    StudyDayType.reinforcement => 'Reinforcement Day',
  };

  /// Missing and unrecognized stored values stay on a Normal Day.
  static StudyDayType fromStorage(String? name) {
    return switch (name) {
      'reinforcement' => StudyDayType.reinforcement,
      _ => StudyDayType.normal,
    };
  }
}
