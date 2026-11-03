/// Optional, versioned explanation of what a deep report actually measured.
/// Unknown contracts never authorize a posture or native-equivalence claim.
class DeepAssessmentEvidence {
  const DeepAssessmentEvidence(this.reps);
  final Map<int, DeepRepEvidence> reps;

  static DeepAssessmentEvidence? parseReport(Map<String, dynamic> report) {
    final value = report['assessmentEvidence'];
    if (value is! Map ||
        value['schema'] != 'bpt.deep-assessment-evidence.v1' ||
        value['coordinateSystem'] != 'h36m17_gravity_aligned_world_m' ||
        value['referenceType'] != 'estimated_geometry_not_ground_truth' ||
        value['reps'] is! List ||
        report['reps'] is! List ||
        value['exerciseId'] is! String ||
        value['exerciseId'] != report['exerciseId'] ||
        value['sourceTimeBasis'] != 'video_ms' ||
        value['fps'] is! num ||
        !value['fps'].isFinite ||
        value['fps'] <= 0 ||
        value['fps'] != report['fps']) {
      return null;
    }
    final owners = <int, Map>{};
    final ambiguous = <int>{};
    for (final rep
        in report['reps'] is List ? report['reps'] as List : const []) {
      if (rep is Map && rep['repIndex'] is int) {
        if (owners.containsKey(rep['repIndex'])) ambiguous.add(rep['repIndex']);
        owners[rep['repIndex']] = rep;
      }
    }
    final reps = <int, DeepRepEvidence>{};
    final duplicates = <int>{};
    final seen = <int>{};
    for (final raw in value['reps'] as List) {
      if (raw is! Map || raw['repIndex'] is! int || raw['repIndex'] < 1) {
        continue;
      }
      final index = raw['repIndex'] as int;
      if (!seen.add(index)) duplicates.add(index);
      final owner = owners[index];
      if (owner == null ||
          ambiguous.contains(index) ||
          raw['startMs'] is! num ||
          !raw['startMs'].isFinite ||
          raw['endMs'] is! num ||
          !raw['endMs'].isFinite ||
          raw['startMs'] < 0 ||
          raw['endMs'] <= raw['startMs'] ||
          !{'left', 'right'}.contains(raw['side']) ||
          ['startMs', 'endMs', 'side'].any((key) => raw[key] != owner[key])) {
        continue;
      }
      if (reps.containsKey(index)) {
        duplicates.add(index);
        continue;
      }
      final metrics = <String, DeepMetricEvidence>{};
      final duplicateMetrics = <String>{};
      final seenMetrics = <String>{};
      if (raw['metrics'] is List) {
        for (final metric in raw['metrics'] as List) {
          if (metric is Map &&
              metric['key'] is String &&
              !seenMetrics.add(metric['key'])) {
            duplicateMetrics.add(metric['key']);
          }
          final parsed = DeepMetricEvidence.parse(metric);
          if (parsed == null) continue;
          final ownerSupport = owner['metricValidity'] is Map
              ? owner['metricValidity'][parsed.key]
              : null;
          final support = DeepEvidenceSupport.parse(ownerSupport);
          if (support == null ||
              support.available != parsed.measurement.available ||
              support.reasons.length != parsed.measurement.reasons.length ||
              support.reasons.any(
                  (reason) => !parsed.measurement.reasons.contains(reason)) ||
              ownerSupport['minimumJointSupport'] !=
                  metric['measurement']['minimumJointSupport']) {
            continue;
          }
          if (metrics.containsKey(parsed.key)) duplicateMetrics.add(parsed.key);
          metrics[parsed.key] = parsed;
        }
      }
      for (final key in duplicateMetrics) {
        metrics.remove(key);
      }
      reps[index] = DeepRepEvidence(
          metrics, DeepNativeComparison.parse(raw['nativeComparison']));
    }
    for (final index in duplicates) {
      reps.remove(index);
    }
    final baseline = (report['reps'] as List)
        .whereType<Map>()
        .take(3)
        .map((r) => r['repIndex'])
        .toList();
    for (final rep in reps.values) {
      // A stale baseline invalidates only its dependent measurements.
      rep.metrics.removeWhere((key, metric) =>
          metric.referenceReps.isNotEmpty &&
          (metric.referenceReps.length != baseline.length ||
              List.generate(baseline.length, (i) => i)
                  .any((i) => metric.referenceReps[i] != baseline[i])));
    }
    return DeepAssessmentEvidence(Map.unmodifiable(reps.map((key, value) =>
        MapEntry(
            key,
            DeepRepEvidence(
                Map.unmodifiable(value.metrics), value.nativeComparison)))));
  }
}

class DeepRepEvidence {
  const DeepRepEvidence(this.metrics, this.nativeComparison);
  final Map<String, DeepMetricEvidence> metrics;
  final DeepNativeComparison? nativeComparison;
}

class DeepEvidenceSupport {
  const DeepEvidenceSupport(this.available, this.reasons);
  final bool available;
  final List<String> reasons;

  static DeepEvidenceSupport? parse(Object? raw) {
    if (raw is! Map || !{'available', 'withheld'}.contains(raw['assessment'])) {
      return null;
    }
    final reasons = _strings(raw['reasons']);
    if (reasons == null ||
        (raw['assessment'] == 'available' && reasons.isNotEmpty) ||
        (raw['assessment'] == 'withheld' && reasons.isEmpty)) {
      return null;
    }
    return DeepEvidenceSupport(raw['assessment'] == 'available', reasons);
  }
}

List<String>? _strings(Object? value) =>
    value is List && value.every((item) => item is String && item.isNotEmpty)
        ? List<String>.unmodifiable(value)
        : null;

class DeepMetricEvidence {
  const DeepMetricEvidence(
      this.key,
      this.definition,
      this.unit,
      this.coordinateType,
      this.referenceType,
      this.referenceReps,
      this.measurement,
      this.postureAssessment);
  final String key, definition, unit, coordinateType, referenceType;
  final List<int> referenceReps;
  final DeepEvidenceSupport measurement, postureAssessment;

  static const _units = {
    'knee': 'deg',
    'hip': 'deg',
    'elbow': 'deg',
    'shoulder': 'deg',
    'torso': 'deg',
    'depthAngleDeg': 'deg',
    'romDeg': 'deg',
    'tempoSeconds': 's',
    'depthMeters': 'm',
    'handPath': 'm',
    'trunkStdDeg': 'deg',
    'symmetryMaxDeg': 'deg',
    'depthDriftDeg': 'deg',
    'romDropDeg': 'deg',
    'tempoDriftRatio': 'ratio',
  };
  static String _coordinate(String key) => switch (key) {
        'torso' ||
        'trunkStdDeg' =>
          'unsigned_gravity_aligned_torso_inclination',
        'depthMeters' => 'world_pelvis_vertical',
        'handPath' => 'pelvis_relative_wrist_midpoint',
        'tempoSeconds' || 'tempoDriftRatio' => 'time_from_primary_angle',
        _ => 'joint_interior_angle',
      };
  static DeepMetricEvidence? parse(Object? raw) {
    if (raw is! Map ||
        !_units.containsKey(raw['key']) ||
        raw['unit'] != _units[raw['key']] ||
        raw['definition'] is! String ||
        (raw['definition'] as String).trim().isEmpty ||
        raw['coordinateType'] != _coordinate(raw['key'])) {
      return null;
    }
    final key = raw['key'] as String;
    final baseline =
        {'depthDriftDeg', 'romDropDeg', 'tempoDriftRatio'}.contains(key);
    if (raw['referenceType'] !=
        (baseline ? 'first_up_to_three_reps_median' : 'within_declared_rep')) {
      return null;
    }
    final refs = raw['referenceReps'];
    if (refs is! List ||
        refs.any((v) => v is! int || v < 1) ||
        refs.toSet().length != refs.length ||
        (baseline ? refs.isEmpty || refs.length > 3 : refs.isNotEmpty)) {
      return null;
    }
    final support = DeepEvidenceSupport.parse(raw['measurement']);
    final posture = DeepEvidenceSupport.parse(raw['postureAssessment']);
    final minimum = raw['measurement'] is Map
        ? raw['measurement']['minimumJointSupport']
        : null;
    if (support == null ||
        (support.available && minimum == null) ||
        posture == null ||
        posture.available ||
        posture.reasons.length != 1 ||
        posture.reasons.single != 'validated_posture_target_missing' ||
        (minimum != null &&
            (minimum is! num ||
                !minimum.isFinite ||
                minimum < 0 ||
                minimum > 1))) {
      return null;
    }
    return DeepMetricEvidence(
        key,
        raw['definition'],
        raw['unit'],
        raw['coordinateType'],
        raw['referenceType'],
        List<int>.unmodifiable(refs),
        support,
        posture);
  }
}

class DeepNativeComparison {
  const DeepNativeComparison(
      this.support, this.comparableKeys, this.unassessedKeys);
  final DeepEvidenceSupport support;
  final List<String> comparableKeys, unassessedKeys;
  static DeepNativeComparison? parse(Object? raw) {
    final support = DeepEvidenceSupport.parse(raw);
    if (raw is! Map || support == null || support.available) {
      return null;
    }
    final comparable = _strings(raw['comparableKeys']);
    final unassessed = _strings(raw['unassessedKeys']);
    if (support.reasons.length != 1 ||
        !{'native_metric_contract_missing', 'no_shared_metric_contract'}
            .contains(support.reasons.single) ||
        comparable == null ||
        comparable.isNotEmpty ||
        unassessed == null) {
      return null;
    }
    return DeepNativeComparison(support, comparable, unassessed);
  }
}
