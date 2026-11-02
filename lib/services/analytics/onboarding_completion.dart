import '../../core/models/placement.dart';

/// Parameters for `onboarding_completed`.
///
/// [startingLevel] is the placement model's rounded difficulty when this
/// process still has it. Otherwise it is the self-assessment
/// (`new_user`, `beginner`, `intermediate`, or `expert`). The numeric
/// estimate is not stored after the test, so a later launch uses the
/// self-assessment. `placement_test_completed` already carried the number.
class OnboardingCompletion {
  const OnboardingCompletion({
    this.dailyGoalMinutes,
    this.startingLevel,
    this.startingMethod,
  });

  final int? dailyGoalMinutes;
  final Object? startingLevel;
  final String? startingMethod;

  static OnboardingCompletion assemble({
    required int dailyGoalMinutes,
    required PlacementSelfAssessment? selfAssessment,
    int? estimatedLevel,
  }) {
    final method = switch (selfAssessment) {
      PlacementSelfAssessment.newUser => 'manual_selection',
      PlacementSelfAssessment.beginner ||
      PlacementSelfAssessment.intermediate ||
      PlacementSelfAssessment.expert => 'placement_test',
      null => null,
    };
    final Object? level =
        estimatedLevel ??
        switch (selfAssessment) {
          PlacementSelfAssessment.newUser => 'new_user',
          PlacementSelfAssessment.beginner => 'beginner',
          PlacementSelfAssessment.intermediate => 'intermediate',
          PlacementSelfAssessment.expert => 'expert',
          null => null,
        };
    return OnboardingCompletion(
      dailyGoalMinutes: dailyGoalMinutes,
      startingLevel: level,
      startingMethod: method,
    );
  }
}
