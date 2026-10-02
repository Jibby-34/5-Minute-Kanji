/// How many minutes a day the user wants to spend.
///
/// The app already limits a day by new kanji rather than by minutes, so a goal
/// is translated into that existing setting instead of being stored as a
/// second, competing limit.
class DailyGoal {
  const DailyGoal(this.minutes);

  static const recommended = DailyGoal(5);

  /// Offered as one-tap choices. Anything else goes through Custom.
  static const presets = [DailyGoal(5), DailyGoal(10), DailyGoal(15)];

  static const int minCustomMinutes = 3;
  static const int maxCustomMinutes = 30;

  final int minutes;

  String get label => '$minutes minutes';

  @override
  bool operator ==(Object other) =>
      other is DailyGoal && minutes == other.minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() => 'DailyGoal($minutes)';
}
