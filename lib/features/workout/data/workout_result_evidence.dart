import 'workout_evidence.dart';

/// A recorded set, not an allocation of a workout goal or warning events.
class ObservedWorkoutSet {
  const ObservedWorkoutSet({
    required this.number,
    required this.reps,
    required this.weightKg,
    required this.warningEvents,
    this.localVideoPath,
    this.remoteVideoUrl,
  });

  final int number;
  final int reps;
  final num? weightKg;
  final int? warningEvents;
  final String? localVideoPath;
  final String? remoteVideoUrl;
}

/// Presentation facts kept separate from planned sets and legacy correctness.
class WorkoutResultEvidence {
  const WorkoutResultEvidence._({
    required this.sets,
    required this.completeBreakdown,
    required this.completedSets,
    required this.volumeKg,
    required this.recordedWeightKg,
  });

  final List<ObservedWorkoutSet> sets;
  final bool completeBreakdown;
  final int? completedSets;
  final num? volumeKg;
  final num? recordedWeightKg;

  static int? _count(Object? value) =>
      value is int && value >= 0 && value <= 2147483647 ? value : null;

  static num? _weight(Object? value) =>
      value is num && value.isFinite && value >= 0 ? value : null;

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static List<ObservedWorkoutSet>? _readSets(Object? raw) {
    if (raw is! List) return null;
    final result = <ObservedWorkoutSet>[];
    final numbers = <int>{};
    for (final (index, value) in raw.indexed) {
      if (value is! Map) return null;
      final reps = _count(value['reps']);
      if (value.containsKey('setNumber') &&
          value.containsKey('setIndex') &&
          value['setNumber'] != value['setIndex']) {
        return null;
      }
      final number = value.containsKey('setNumber')
          ? _count(value['setNumber'])
          : value.containsKey('setIndex')
              ? _count(value['setIndex'])
              : index + 1;
      if (reps == null ||
          number == null ||
          number == 0 ||
          !numbers.add(number)) {
        return null;
      }
      result.add(ObservedWorkoutSet(
        number: number,
        reps: reps,
        weightKg: value['weightRecorded'] == false
            ? null
            : _weight(value['weightKg']),
        warningEvents: _count(value['badCount']),
        localVideoPath: _text(value['videoLocalPath']),
        remoteVideoUrl:
            _text(value['videoRemoteUrl']) ?? _text(value['videoUrl']),
      ));
    }
    return result;
  }

  factory WorkoutResultEvidence.fromResult(Map<String, dynamic> result) {
    final total = _count(result['totalReps']);
    final native = WorkoutEvidence.details(
      WorkoutEvidence.summaryObject(result['poseMetricsSummary']),
      completedReps: total,
    );
    final supplied = result['setResultsValid'] == false
        ? null
        : _readSets(result['setResults']);
    var sets = native == null ? supplied : _readSets(native['sets']);
    // The supported native envelope owns counts/weights. Attach media only from
    // a matching row; a conflicting presentation copy cannot replace its facts.
    if (native != null && sets != null && supplied != null) {
      final byNumber = {for (final set in supplied) set.number: set};
      sets = sets.map((set) {
        final media = byNumber[set.number];
        final matches =
            media?.reps == set.reps && media?.weightKg == set.weightKg;
        return ObservedWorkoutSet(
          number: set.number,
          reps: set.reps,
          weightKg: set.weightKg,
          warningEvents: set.warningEvents,
          localVideoPath: matches ? media?.localVideoPath : null,
          remoteVideoUrl: matches ? media?.remoteVideoUrl : null,
        );
      }).toList();
    }
    final recordedReps = sets?.fold<int>(0, (sum, set) => sum + set.reps);
    // Contradictory rows are not an attributable set breakdown. Raw inputs stay
    // untouched for compatibility; the known workout total remains available.
    if (total != null && recordedReps != null && recordedReps > total) {
      sets = null;
    }
    final complete = sets != null && total != null && recordedReps == total;
    final knownSets = sets ?? const <ObservedWorkoutSet>[];
    // Unversioned totalVolume may itself be a legacy goal/weight estimate.
    num? volume;
    if (complete && knownSets.every((set) => set.weightKg != null)) {
      volume =
          knownSets.fold<num>(0, (sum, set) => sum + set.reps * set.weightKg!);
    }
    num? weight = native == null && result['weightRecorded'] != false
        ? _weight(result['weightKg'])
        : null;
    for (final set in knownSets) {
      if (set.weightKg != null && (weight == null || set.weightKg! > weight)) {
        weight = set.weightKg;
      }
    }
    return WorkoutResultEvidence._(
      sets: List.unmodifiable(knownSets),
      completeBreakdown: complete,
      completedSets:
          complete ? knownSets.length : _count(result['completedSets']),
      volumeKg: volume,
      recordedWeightKg: weight,
    );
  }
}
