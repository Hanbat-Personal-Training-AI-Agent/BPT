import 'package:bpt/features/workout/data/kori_feedback_lines.dart';
import 'package:bpt/features/workout/data/native_pose_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('method names match the native bridge', () {
    expect(
      [
        NativePoseChannel.onPoseUpdate,
        NativePoseChannel.onFeedback,
        NativePoseChannel.onSetEnd,
        NativePoseChannel.setVoiceMuted,
        NativePoseChannel.startSet,
        NativePoseChannel.endSet,
      ],
      ['onPoseUpdate', 'onFeedback', 'onSetEnd', 'setVoiceMuted', 'startSet', 'endSet'],
    );
  });

  test('onFeedback args parse with scope', () {
    final rep = NativeFeedback.parse({'key': 'tracking_lost', 'scope': 'rep'})!;
    expect(rep.key, 'tracking_lost');
    expect(rep.n, isNull);
    expect(rep.isSetScope, isFalse);
    final set = NativeFeedback.parse({'key': 'pushup_no_lockout', 'n': 2, 'scope': 'set'})!;
    expect(set.n, 2);
    expect(set.isSetScope, isTrue);
    expect(NativeFeedback.parse({'n': 1}), isNull);
    expect(NativeFeedback.parse(null), isNull);
  });

  test('voice reply renders the dart line ({n}, locale) and ignores unknown keys', () {
    expect(koriVoiceReply('pushup_no_lockout', 2, isKo: true), {
      'text': '올라올 때 팔을 다 안 편 렙이 2번 있었어. 위에서 팔꿈치를 끝까지 펴 줘.',
      'lang': 'ko-KR',
    });
    expect(koriVoiceReply('tracking_lost', null, isKo: false)!['lang'], 'en-US');
    expect(koriVoiceReply('tracking_lost', null, isKo: false)!['text'],
        koriFeedbackLines['tracking_lost']!.en);
    expect(koriVoiceReply('no_such_key', null, isKo: true), isNull);
  });

  test('onPoseUpdate pose3d states are parsed and never hidden', () {
    final warm = NativePose3DStatus.parse({
      'rep': 0,
      'pose3d': {'state': 'warming_up', 'filled': 12, 'window': 27, 'usable': false},
    })!;
    expect(warm.message(isKo: true), '3D 자세 준비 중 (12/27)');
    expect(NativePose3DStatus.parse({'pose3d': {'state': 'tracking_lost'}})!.message(isKo: true), contains('판정 멈춤'));
    expect(NativePose3DStatus.parse({'pose3d': {'state': 'bad_3d'}})!.message(isKo: false), contains('not judged'));
    expect(NativePose3DStatus.parse({'pose3d': {'state': 'partial_3d', 'usable': true}})!.message(isKo: true), isNull);
    final ok = NativePose3DStatus.parse({'pose3d': {'state': 'ok', 'usable': true}})!;
    expect(ok.usable, isTrue);
    expect(ok.message(isKo: true), isNull);
    expect(NativePose3DStatus.parse({'rep': 1}), isNull, reason: 'no 3D path');
  });
}
