/// 운동 카메라 채널 `bpt/native_pose_camera/<viewId>` 계약.
/// 네이티브 쪽: ios/Runner/NativePose/Bridge/WorkoutSessionBridge.swift.
///
/// 네이티브 → Flutter
/// - `onPoseUpdate` {rep, status, done}
/// - `onFeedback` {key, n?, scope: "rep"|"set"} → 답으로 {text, lang} 을 돌려주면 네이티브가 그 대사를
///   말한다 (대사 원문은 kori_feedback_lines.dart 에만 둔다). null 이면 말하지 않는다.
/// - `onSetEnd` {setIndex, videoLocalPath?, worstJoint?}
///
/// Flutter → 네이티브
/// - `setVoiceMuted` {muted}, `startSet` {setIndex}, `endSet` {setIndex}
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
  const NativePose3DStatus({required this.state, this.filled = 0, this.window = 27, this.usable = false});

  final String state; // warming_up | tracking_lost | partial_3d | bad_3d | ok
  final int filled;
  final int window;
  final bool usable;

  static NativePose3DStatus? parse(Object? arguments) {
    if (arguments is! Map) return null;
    final p = arguments['pose3d'];
    if (p is! Map || p['state'] is! String) return null;
    return NativePose3DStatus(
      state: p['state'] as String,
      filled: (p['filled'] as num?)?.toInt() ?? 0,
      window: (p['window'] as num?)?.toInt() ?? 27,
      usable: p['usable'] == true,
    );
  }

  /// 사용자에게 보일 안내 (ok 이면 null — 표시 안 함).
  String? message({required bool isKo}) {
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
