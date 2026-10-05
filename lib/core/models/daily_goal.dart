/// How many minutes a day the user wants the normal session planned around.
///
/// Stored as [AppSettings.dailyStudyMinutes]. Onboarding also derives a
/// new-kanji allowance from it; that allowance stays a separate cap.
class DailyGoal {
  const DailyGoal(this.minutes);

  static const recommended = DailyGoal(5);

  /// Offered as one-tap choices. Anything else goes through Custom.
  static const presets = [
    DailyGoal(5),
    DailyGoal(10),
    DailyGoal(15),
    DailyGoal(20),
    DailyGoal(30),
  ];

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
