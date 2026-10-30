/// Completion and delivered rule events are not validated posture/correct-rep evidence.
/// The current client has no independent full-form validation contract, including for legacy scores.
class WorkoutEvidence {
  static const key = 'workoutEvidence';

  static Map<String, dynamic> nativeSummary({
    required int completedReps,
    required int recordedWarningEvents,
    required List<Map<String, dynamic>> sets,
  }) =>
      {
        key: {
          'version': 1,
          'source': 'native_scoped_rule_events',
          'completedReps': completedReps,
          'recordedWarningEvents': recordedWarningEvents,
          'warningEventScope': 'delivered_rep_scope_only',
          'formAssessment': 'not_available',
          'assessedReps': null,
          'validatedCorrectReps': null,
          'postureScore': null,
          'legacyCorrectnessFields': 'zero_placeholders_not_assessments',
          'sets': sets,
        },
      };

  static Map<String, dynamic>? details(Map<String, dynamic>? summary) {
    final raw = summary?[key];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// A goal is a completion target, not a percentage of correct form. No target means no percentage.
  static int? completionPercent(int completed, int target) =>
      target > 0 ? ((completed / target) * 100).clamp(0, 100).round() : null;
}
