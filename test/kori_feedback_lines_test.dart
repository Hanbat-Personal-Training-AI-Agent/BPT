import 'package:bpt/features/workout/data/kori_feedback_lines.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기획 문서의 키가 모두 있다', () {
    const keys = [
      'pushup_hip_sag', 'pushup_hip_pike', 'pushup_shallow', 'pushup_no_lockout',
      'pushup_head_drop', 'pushup_head_up', 'pushup_hand_position',
      'pushup_depth_fade',
      'squat_hips_first', 'squat_shallow', 'squat_no_lockout', 'squat_lean_drift',
      'squat_depth_fade', 'squat_knee_valgus', 'squat_heel_rise',
      'row_torso_swing', 'row_standing_up', 'row_short_pull', 'row_head_up',
      'row_shrug',
      'setup_side_view', 'setup_full_body', 'setup_phone_upright',
      'setup_front_view', 'tracking_lost', 'praise_fixed', 'praise_clean_set',
      'set_summary',
    ];
    expect(koriFeedbackLines.keys.toSet(), keys.toSet());
    for (final key in koriDemoWarningKeyByExercise.values) {
      expect(koriFeedbackLines[key]!.kind, KoriFeedbackKind.warning);
    }
  });

  test('{n} {reps} {k} 를 채운다', () {
    expect(
      koriFeedbackLines['squat_no_lockout']!.render(isKo: true, n: 3),
      '다 안 일어선 렙이 3번 있었어. 위에서 무릎이랑 엉덩이를 끝까지 펴 줘.',
    );
    expect(
      koriFeedbackLines['praise_clean_set']!.render(isKo: true, reps: 12),
      '12개 다 좋았어! 수고했어',
    );
    expect(
      koriFeedbackLines['set_summary']!.render(isKo: true, k: 2),
      '수고했어! 고칠 점 2개 정리해 뒀어',
    );
  });

  test('마지막 문장을 보조 문구로 나눈다', () {
    expect(splitKoriLine('잠깐! 엉덩이 처졌어. 배에 힘 줘!'),
        (title: '잠깐! 엉덩이 처졌어.', subtitle: '배에 힘 줘!'));
    expect(splitKoriLine('좋아, 방금 렙 딱 좋았어!'),
        (title: '좋아, 방금 렙 딱 좋았어!', subtitle: ''));
  });
}
