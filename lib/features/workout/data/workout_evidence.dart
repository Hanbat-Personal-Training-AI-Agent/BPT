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

  /// A malformed/legacy scalar never crashes record loading or becomes assessed evidence.
  static Map<String, dynamic>? summaryObject(Object? raw) {
    if (raw is! Map || raw.keys.any((key) => key is! String)) return null;
    return Map<String, dynamic>.from(raw);
  }

  static Map<String, dynamic>? details(Map<String, dynamic>? summary,
      {int? completedReps}) {
    final e = summaryObject(summary?[key]);
    if (e == null ||
        e['version'] is! int ||
        e['version'] != 1 ||
        e['source'] != 'native_scoped_rule_events' ||
        e['warningEventScope'] != 'delivered_rep_scope_only' ||
        e['formAssessment'] != 'not_available' ||
        e['legacyCorrectnessFields'] != 'zero_placeholders_not_assessments') {
      return null;
    }
    for (final field in [
      'assessedReps',
      'validatedCorrectReps',
      'postureScore'
    ]) {
      if (!e.containsKey(field) || e[field] != null) return null;
    }
    bool count(Object? v) => v is int && v >= 0 && v <= 2147483647;
    if (!count(e['completedReps']) ||
        !count(e['recordedWarningEvents']) ||
        e['sets'] is! List) {
      return null;
    }
    var reps = 0, events = 0;
    for (final raw in e['sets'] as List) {
      final set = summaryObject(raw);
      if (set == null || !count(set['reps']) || !count(set['badCount'])) {
        return null;
      }
      final weight = set['weightKg'];
      if (weight is! num || !weight.isFinite || weight < 0) return null;
      reps += set['reps'] as int;
      events += set['badCount'] as int;
    }
    if (completedReps != null && completedReps != e['completedReps']) {
      return null;
    }
    return reps == e['completedReps'] && events == e['recordedWarningEvents']
        ? e
        : null;
  }

  /// A goal is a completion target, not a percentage of correct form. No target means no percentage.
  static int? completionPercent(int completed, int target) =>
      target > 0 ? ((completed / target) * 100).clamp(0, 100).round() : null;
}
