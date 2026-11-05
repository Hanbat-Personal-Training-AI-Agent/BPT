import 'dart:async';

import '../../onboarding/services/calibration_result_store.dart';

/// An explicit weight for one saved calibration, never inferred from fit error.
class MotionProfileDeclaration {
  const MotionProfileDeclaration(this.jobId, this.weight, this.source);
  final String jobId, source;
  final double weight;
  static MotionProfileDeclaration? fromEnvironment() {
    const job = String.fromEnvironment('BPT_MOTION_PROFILE_JOB_ID');
    const raw = String.fromEnvironment('BPT_MOTION_PROFILE_WEIGHT');
    const source = String.fromEnvironment('BPT_MOTION_PROFILE_WEIGHT_SOURCE');
    final weight = double.tryParse(raw);
    if (job.isEmpty ||
        source.isEmpty ||
        weight == null ||
        !weight.isFinite ||
        weight <= 0 ||
        weight > 1) {
      return null;
    }
    return MotionProfileDeclaration(job, weight, source);
  }
}

class MotionProfileAssessment {
  const MotionProfileAssessment(this.payload, this.reason);
  final Map<String, dynamic>? payload;
  final String? reason;
  static MotionProfileAssessment assess(
    Map<String, dynamic>? saved, {
    required String ownerId,
    required MotionProfileDeclaration? declaration,
  }) {
    MotionProfileAssessment held(String reason) =>
        MotionProfileAssessment(null, reason);
    if (ownerId.trim().isEmpty ||
        saved == null ||
        saved['ownerId'] != ownerId) {
      return held('owner_or_result_missing');
    }
    if (saved['stub'] != false) return held('non_stub_provenance_unverified');
    if (saved['schemaVersion'] != 1 ||
        saved['bodyModel'] != 'smpl_neutral_v1.1.0') {
      return held('unsupported_smpl_provenance');
    }
    final beta = saved['smplBeta'];
    final bone = saved['boneLengthData'];
    if (beta is! List ||
        beta.length != 10 ||
        beta.any((v) => v is! num || !v.isFinite) ||
        bone is! Map ||
        bone['unit'] != 'cm' ||
        bone['skeleton'] != 'h36m17' ||
        bone['pose'] != 'rest') {
      return held('unsupported_shape_or_bone_definition');
    }
    final quality = saved['quality'];
    final views = quality is Map ? quality['perView'] : null;
    final heightError = quality is Map ? quality['heightErrorCm'] : null;
    final hasEvidence =
        (heightError is num && heightError.isFinite && heightError >= 0) ||
            (views is Map &&
                views.values.any(
                  (v) =>
                      v is Map &&
                      v['reprojectionErrorPx'] is num &&
                      (v['reprojectionErrorPx'] as num).isFinite &&
                      v['reprojectionErrorPx'] >= 0,
                ));
    if (!hasEvidence) return held('quality_evidence_missing');
    if (declaration == null ||
        declaration.jobId.trim().isEmpty ||
        declaration.jobId.length > 128 ||
        declaration.source.length > 512 ||
        declaration.jobId != saved['jobId'] ||
        !declaration.weight.isFinite ||
        declaration.weight <= 0 ||
        declaration.weight > 1 ||
        declaration.source.trim().isEmpty) {
      return held('per_profile_weight_declaration_missing');
    }
    return MotionProfileAssessment({
      'schema': 'bpt.account-motion-profile.v1',
      'scope': 'same_account_live_camera_assumption',
      'jobId': declaration.jobId,
      'calibration': {
        'schemaVersion': 1,
        'stub': false,
        'bodyModel': saved['bodyModel'],
        'smplBeta': beta,
        'boneLengthData': Map<String, dynamic>.from(bone),
        'quality': quality,
      },
      'engineeringWeight': {
        'value': declaration.weight,
        'source': declaration.source,
        'meaning': 'explicit_engineering_weight_not_accuracy_probability',
      },
    }, null);
  }
}

/// Each begin clears native state before async loading. Both sides reject stale bindings.
class MotionObserverProfileBridge {
  MotionObserverProfileBridge({required this.invoke, this.declaration});
  static const enabled = bool.fromEnvironment(
    'BPT_MOTION_OBSERVER_ACCOUNT_PROFILE',
  );
  final Future<dynamic> Function(String, Map<String, dynamic>) invoke;
  final MotionProfileDeclaration? declaration;
  int _generation = 0;
  bool _disposed = false;
  static int _next = 0;
  Future<void> bind(CalibrationResultStore store) async {
    if (_disposed) return;
    final generation = ++_generation;
    final binding =
        'profile-${DateTime.now().microsecondsSinceEpoch}-${++_next}';
    final owner = store.ownerId;
    try {
      final ack = await invoke(
          'beginMotionObserverProfileBinding', {'binding': binding});
      if (ack is! Map || ack['accepted'] != true) return;
      if (_disposed ||
          generation != _generation ||
          !store.isCurrent ||
          owner == null) {
        return;
      }
      final saved = await store.load();
      if (_disposed ||
          generation != _generation ||
          !store.isCurrent ||
          store.ownerId != owner) {
        return;
      }
      final assessed = MotionProfileAssessment.assess(
        saved,
        ownerId: owner,
        declaration: declaration,
      );
      await invoke('setMotionObserverProfile', {
        'binding': binding,
        if (assessed.payload != null) 'profile': assessed.payload,
        if (assessed.reason != null) 'withheldReason': assessed.reason,
      });
    } catch (_) {
      // A disposed native channel cannot retain data in a replacement view.
    }
  }

  void cancelPendingStart() {
    _generation++;
  }

  Future<void> bindAfterStart(
      Future<dynamic>? started, CalibrationResultStore store,
      {required bool Function() stillCurrent}) async {
    final generation = _generation;
    try {
      await started;
    } catch (_) {
      return;
    }
    if (_disposed ||
        generation != _generation ||
        !store.isCurrent ||
        !stillCurrent()) {
      return;
    }
    await bind(store);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(
      invoke('beginMotionObserverProfileBinding', {
        'binding':
            'cleared-${DateTime.now().microsecondsSinceEpoch}-${++_next}',
      }).catchError((_) => null),
    );
  }
}
