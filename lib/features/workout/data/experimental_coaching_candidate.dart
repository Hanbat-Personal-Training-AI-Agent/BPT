/// Versioned opt-in proposals from the native candidate branch; never normal-form certification.
class ExperimentalCoachingCandidate {
  const ExperimentalCoachingCandidate(
      {required this.proposalId,
      required this.ruleId,
      required this.assessment,
      required this.experimentId,
      required this.source,
      required this.unresolvedComponents});
  final String proposalId, ruleId, assessment, experimentId;
  final Map<String, dynamic> source;
  final int unresolvedComponents;
  bool get isSynthetic => source['synthetic_fixture'] == true;
  static const _cues = {
    'pushup.camera_body_line_transfer': (
      '몸통과 골반 정렬을 확인해 주세요.',
      'Check your trunk and pelvis alignment.'
    ),
    'pushup.projected_arm_range': (
      '선택한 팔 벌림 범위를 확인해 주세요.',
      'Check the arm range selected for this variation.'
    ),
    'pushup.bottom_target': (
      '선택한 푸시업 깊이를 확인해 주세요.',
      'Check your selected push-up depth.'
    ),
    'pushup.top_extension_target': (
      '선택한 상단 팔 폄 범위를 확인해 주세요.',
      'Check your selected elbow extension target.'
    ),
    'squat.early_ascent_coordination': (
      '올라올 때 어깨와 골반 움직임을 함께 확인해 주세요.',
      'Check how your shoulders and pelvis rise together.'
    ),
    'squat.bottom_target': (
      '선택한 스쿼트 깊이를 확인해 주세요.',
      'Check your selected squat depth.'
    ),
    'squat.top_extension_target': (
      '선택한 상단 다리 폄 범위를 확인해 주세요.',
      'Check your selected top extension target.'
    ),
    'row.camera_torso_window_transfer': (
      '몸통 움직임이 커졌어요. 선택한 로우 자세를 확인해 주세요.',
      'Your trunk moved through a larger range. Check your selected row variation.'
    ),
    'row.phase_prefix_leg_arm_cooccurrence': (
      '당기는 구간에 다리 움직임도 보였어요. 선택한 로우 변형을 확인해 주세요.',
      'Leg motion also appeared during the pull. Check your selected row variation.'
    )
  };
  String cue({required bool isKo}) {
    final cue = _cues[ruleId]!;
    return isKo ? cue.$1 : cue.$2;
  }

  static ExperimentalCoachingCandidate? parse(dynamic value) {
    if (value is! Map) return null;
    final id = value['ruleId'],
        proposal = value['proposalId'],
        experiment = value['experimentID'];
    if (value['captureId'] is! String ||
        (value['captureId'] as String).isEmpty ||
        (value['captureId'] as String).length > 128 ||
        value['schema'] != 'bpt.coaching-candidate-proposal.v1' ||
        value['authority'] != 'engineering_candidate_not_validated_form' ||
        value['presentation'] != 'visual_only_no_tts' ||
        value['delivery'] != 'proposed' ||
        id is! String ||
        !_cues.containsKey(id) ||
        proposal is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(proposal) ||
        experiment is! String ||
        experiment.isEmpty ||
        experiment.length > 128) {
      return null;
    }
    final meaning = value['predicateMeaning'],
        state = value['predicateState'],
        assessment = value['assessment'];
    if (!((meaning == 'deviation' &&
            state == 'positive_evidence' &&
            assessment == 'deviation_candidate') ||
        (meaning == 'desired_match' &&
            state == 'negative_evidence' &&
            assessment == 'target_not_met_candidate'))) {
      return null;
    }
    final source = value['source'], context = value['context'];
    if (source is! Map ||
        context is! Map ||
        context['flush_tail'] != false ||
        source['source_pts'] is! num ||
        !(source['source_pts'] as num).isFinite ||
        source['source_index'] is! int ||
        source['frame'] is! int ||
        source['epoch'] is! int) {
      return null;
    }
    final unresolved = value['unresolvedComponents'];
    if (unresolved is! int || unresolved < 0 || unresolved > 4) return null;
    return ExperimentalCoachingCandidate(
        proposalId: proposal,
        ruleId: id,
        assessment: assessment as String,
        experimentId: experiment,
        source: {
          ...Map<String, dynamic>.from(source),
          'synthetic_fixture': context['source_kind'] == 'synthetic_fixture'
        },
        unresolvedComponents: unresolved);
  }
}

/// Reject old source packets and expire immediately on uncertainty/lifecycle changes.
class ExperimentalCoachingCandidateInbox {
  ExperimentalCoachingCandidate? current;
  String? _captureId;
  int? _epoch, _index;
  bool accept(dynamic value, {required bool active}) {
    final candidate = ExperimentalCoachingCandidate.parse(value);
    if (!active || candidate == null) return false;
    final capture = (value as Map)['captureId'] as String;
    final epoch = candidate.source['epoch'] as int,
        index = candidate.source['source_index'] as int;
    if (capture == _captureId &&
        (_epoch != null &&
            (epoch < _epoch! ||
                (epoch == _epoch && _index != null && index <= _index!)))) {
      return false;
    }
    _captureId = capture;
    _epoch = epoch;
    _index = index;
    current = candidate;
    return true;
  }

  bool expire(dynamic value) {
    if (current == null ||
        value is! Map ||
        value['schema'] != 'bpt.coaching-candidate-clear.v1' ||
        value['captureId'] != _captureId ||
        value['previousProposalId'] != current?.proposalId) {
      return false;
    }
    final source = value['source'];
    if (source is! Map ||
        source['epoch'] is! int ||
        source['source_index'] is! int) {
      return false;
    }
    final epoch = source['epoch'] as int, index = source['source_index'] as int;
    if (_epoch != null &&
        (epoch < _epoch! ||
            (epoch == _epoch && _index != null && index < _index!))) {
      return false;
    }
    _epoch = epoch;
    _index = index;
    current = null;
    return true;
  }

  void clear() => current = null;
}
