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
