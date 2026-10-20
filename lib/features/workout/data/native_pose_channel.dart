/// 운동 카메라 채널 `bpt/native_pose_camera/<viewId>` 계약.
/// 네이티브 쪽: ios/Runner/NativePose/Bridge/WorkoutSessionBridge.swift.
///
/// 네이티브 → Flutter
/// - `onPoseUpdate` {rep, status, done, pose3d?, setup?} — setup 은 실험용 준비 자세 확인(BPT_EXERCISE_SETUP)일 때만
/// - `onFeedback` {key, n?, scope: "rep"|"set"} → 답으로 {text, lang} 을 돌려주면 네이티브가 그 대사를
///   말한다 (대사 원문은 kori_feedback_lines.dart 에만 둔다). null 이면 말하지 않는다.
/// - `onSetEnd` {setIndex, videoLocalPath?, worstJoint?}
///
/// Flutter → 네이티브
/// - `setVoiceMuted` {muted}, `startSet` {setIndex}, `endSet` {setIndex}
/// - (실험용 준비 자세) `resetSetup`, `setSetupVariant` {variant, reference?}
library;

import 'kori_feedback_lines.dart';

class NativePoseChannel {
  NativePoseChannel._();

  static const String onPoseUpdate = 'onPoseUpdate';
  static const String onFeedback = 'onFeedback';
  static const String onSetEnd = 'onSetEnd';
  static const String setVoiceMuted = 'setVoiceMuted';
  static const String startSet = 'startSet';
  static const String endSet = 'endSet';
  static const String resetSetup = 'resetSetup';
  static const String setSetupVariant = 'setSetupVariant';
}

/// `onFeedback` 인자. `isSetScope` = 세트 끝 요약(참고 등급, n = 세트 안 렙 수).
class NativeFeedback {
  const NativeFeedback({required this.key, this.n, this.isSetScope = false});

  final String key;
  final int? n;
  final bool isSetScope;

  static NativeFeedback? parse(Object? arguments) {
    if (arguments is! Map) return null;
    final key = arguments['key'];
    if (key is! String) return null;
    return NativeFeedback(
      key: key,
      n: (arguments['n'] as num?)?.toInt(),
      isSetScope: arguments['scope'] == 'set',
    );
  }
}

/// `onFeedback` 답: 네이티브 음성이 말할 대사. 모르는 키는 null (말하지 않음).
Map<String, String>? koriVoiceReply(String key, int? n, {required bool isKo}) {
  final line = koriFeedbackLines[key];
  if (line == null) return null;
  return {'text': line.render(isKo: isKo, n: n), 'lang': isKo ? 'ko-KR' : 'en-US'};
}

/// `onPoseUpdate` 의 `pose3d` {state, filled, window, usable} — 실시간 3D(MotionAGFormer-XS) 상태.
/// 자세 판정은 3D로만 하므로 3D가 쓸 수 없는 상태를 화면에 숨기지 않고 보여준다.
/// 네이티브 쪽: WorkoutSessionBridge.swift `Pose3DBridge`.
class NativePose3DStatus {
  const NativePose3DStatus(
      {required this.state, this.filled = 0, this.window = 27, this.usable = false, this.occluded = const []});

  final String state; // warming_up | tracking_lost | partial_3d | bad_3d | ok
  final int filled;
  final int window;
  final bool usable;

  /// 실험용 적응형 관계 제약(BPT_ADAPTIVE_3D=1)일 때만: 2D가 관측되지 않아 관계로 추정한 관절(H36M 번호).
  final List<int> occluded;

  static NativePose3DStatus? parse(Object? arguments) {
    if (arguments is! Map) return null;
    final p = arguments['pose3d'];
    if (p is! Map || p['state'] is! String) return null;
    return NativePose3DStatus(
      state: p['state'] as String,
      filled: (p['filled'] as num?)?.toInt() ?? 0,
      window: (p['window'] as num?)?.toInt() ?? 27,
      usable: p['usable'] == true,
      occluded: (p['occluded'] as List?)?.whereType<num>().map((e) => e.toInt()).toList() ?? const [],
    );
  }

  /// 사용자에게 보일 안내 (ok 이면 null — 표시 안 함).
  String? message({required bool isKo}) {
    if ((state == 'ok' || state == 'partial_3d') && occluded.isNotEmpty) {
      return isKo
          ? '일부 관절이 가려져 직전 관계로 추정하고 있어요 — 그 관절의 판정은 신뢰도가 낮아요'
          : 'Some joints are hidden and estimated from the last relation — lower confidence for them';
    }
    switch (state) {
      case 'warming_up':
        return isKo ? '3D 자세 준비 중 ($filled/$window)' : 'Preparing 3D pose ($filled/$window)';
      case 'tracking_lost':
        return isKo ? '사람이 잘 안 보여요 — 자세 판정 멈춤' : 'Person not visible — form check paused';
      case 'bad_3d':
        return isKo ? '3D 자세 인식이 불안정해요 — 이 구간은 판정 안 함' : '3D pose unreliable — not judged';
      case 'partial_3d':
        return isKo ? '일부 관절 3D 불안정 — 그 관절은 판정 안 함' : 'Some joints unreliable in 3D — those are not judged';
      default:
        return null;
    }
  }
}

/// `onPoseUpdate` 의 `setup` 한 항목 (ExerciseSetupBridge.payload). value 는 같은 프레임의 관절 중심 너비에 대한
/// 비율(또는 몸통 기울기 °)이다. quality: good | low | missing | depth_estimated(측면 — XS 깊이 추정).
class NativeSetupItem {
  const NativeSetupItem({
    required this.key,
    required this.quality,
    this.value,
    this.required = false,
    this.depth = 0,
    this.ref,
    this.cue,
    this.approx = false,
  });

  final String key;
  final String quality;
  final double? value;
  final bool required;
  final double depth;

  /// 사용자가 저장한 내 기준 값 (없으면 null — 그때는 조정 안내도 없다).
  final double? ref;

  /// increase | decrease | null (내 기준 허용 범위 안).
  final String? cue;

  /// grip_width: 손목 중심 간격이라 그립(바 접촉) 너비의 근사.
  final bool approx;

  /// 숫자를 보여도 되는 관측 품질 (low / missing 은 숫자 없이 "측정 중").
  bool get measured => value != null && (quality == 'good' || quality == 'depth_estimated');

  static NativeSetupItem? parse(Object? raw) {
    if (raw is! Map || raw['key'] is! String || raw['quality'] is! String) return null;
    return NativeSetupItem(
      key: raw['key'] as String,
      quality: raw['quality'] as String,
      value: (raw['value'] as num?)?.toDouble(),
      required: raw['required'] == true,
      depth: (raw['depth'] as num?)?.toDouble() ?? 0,
      ref: (raw['ref'] as num?)?.toDouble(),
      cue: raw['cue'] as String?,
      approx: raw['approx'] == true,
    );
  }
}

/// `onPoseUpdate` 의 `setup` — 실험용 개인화 준비 자세 확인 (네이티브 ExerciseSetup.swift).
/// phase: unavailable | measuring | holding | ready. ready 는 "관측이 안정적"이라는 뜻이지 올바른 자세 판정이 아니다.
class NativeSetupStatus {
  const NativeSetupStatus({
    required this.phase,
    this.exercise,
    this.variant,
    this.progress = 0,
    this.moving = false,
    this.items = const [],
    this.snapshot,
  });

  final String phase;
  final String? exercise;
  final String? variant;
  final double progress;
  final bool moving;
  final List<NativeSetupItem> items;

  /// ready 순간의 항목 값 (내 기준으로 저장할 값).
  final Map<String, double>? snapshot;

  bool get isReady => phase == 'ready';

  static NativeSetupStatus? parse(Object? arguments) {
    if (arguments is! Map) return null;
    final p = arguments['setup'];
    if (p is! Map || p['phase'] is! String) return null;
    final snap = p['snapshot'];
    return NativeSetupStatus(
      phase: p['phase'] as String,
      exercise: p['exercise'] as String?,
      variant: p['variant'] as String?,
      progress: (p['progress'] as num?)?.toDouble() ?? 0,
      moving: p['moving'] == true,
      items: [
        for (final raw in (p['items'] as List?) ?? const [])
          if (NativeSetupItem.parse(raw) case final item?) item,
      ],
      snapshot: snap is Map
          ? {
              for (final e in snap.entries)
                if (e.key is String && e.value is num) e.key as String: (e.value as num).toDouble(),
            }
          : null,
    );
  }
}
