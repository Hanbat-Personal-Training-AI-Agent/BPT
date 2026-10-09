/// 운동 중 코리 피드백 대사 목록 (기획 문서 "코리 피드백 대사"의 키·대사 그대로).
///
/// 네이티브 평가기가 `onFeedback` 으로 키를 보내면 이 목록에서 대사를 찾아 말풍선에
/// 띄운다. `{n}`(해당 렙 수), `{reps}`(세트 렙 수), `{k}`(고칠 점 개수)는 [render]에서
/// 채운다. 벤치프레스·데드리프트 대사는 기획 문서에 아직 없다.
library;

enum KoriFeedbackKind {
  /// 자세 경고 (분홍 말풍선, 걱정하는 코리).
  warning,

  /// 칭찬 (초록 말풍선, 응원하는 코리).
  praise,

  /// 촬영 위치·인식 안내 (보라 말풍선, 생각하는 코리).
  setup,
}

class KoriFeedbackLine {
  const KoriFeedbackLine({
    required this.key,
    required this.kind,
    required this.ko,
    required this.en,
  });

  final String key;
  final KoriFeedbackKind kind;
  final String ko;
  final String en;

  String render({required bool isKo, int? n, int? reps, int? k}) {
    var text = isKo ? ko : en;
    if (n != null) text = text.replaceAll('{n}', '$n');
    if (reps != null) text = text.replaceAll('{reps}', '$reps');
    if (k != null) text = text.replaceAll('{k}', '$k');
    return text;
  }
}

/// 말풍선 두 줄(굵은 제목 + 보조 문구)로 나눈다. 마지막 문장을 보조 문구로 쓰고,
/// 한 문장이면 제목만 쓴다.
({String title, String subtitle}) splitKoriLine(String text) {
  final boundary = RegExp(r'[.!?](?=\s)');
  final matches = boundary.allMatches(text).toList();
  if (matches.isEmpty) return (title: text.trim(), subtitle: '');
  final cut = matches.last.end;
  return (
    title: text.substring(0, cut).trim(),
    subtitle: text.substring(cut).trim(),
  );
}

const List<KoriFeedbackLine> _lines = [
  // 푸시업
  KoriFeedbackLine(
    key: 'pushup_hip_sag',
    kind: KoriFeedbackKind.warning,
    ko: '잠깐! 엉덩이 처졌어. 배에 힘 줘!',
    en: 'Wait! Your hips sagged. Brace your core!',
  ),
  KoriFeedbackLine(
    key: 'pushup_hip_pike',
    kind: KoriFeedbackKind.warning,
    ko: '엉덩이가 너무 높아! 몸 일자로 내려 줘',
    en: 'Hips too high! Bring your body into a straight line',
  ),
  KoriFeedbackLine(
    key: 'pushup_shallow',
    kind: KoriFeedbackKind.warning,
    ko: '이번엔 얕았어! 조금만 더 내려가 줘',
    en: 'That one was shallow! Go down a little more',
  ),
  KoriFeedbackLine(
    key: 'pushup_no_lockout',
    kind: KoriFeedbackKind.warning,
    ko: '올라올 때 팔을 다 안 편 렙이 {n}번 있었어. 위에서 팔꿈치를 끝까지 펴 줘.',
    en: "You didn't fully straighten your arms on {n} reps. Lock out your elbows at the top.",
  ),
  KoriFeedbackLine(
    key: 'pushup_head_drop',
    kind: KoriFeedbackKind.warning,
    ko: '고개가 떨어진 렙이 {n}번 있었어. 목은 몸이랑 일자로!',
    en: 'Your head dropped on {n} reps. Keep your neck in line with your body!',
  ),
  KoriFeedbackLine(
    key: 'pushup_head_up',
    kind: KoriFeedbackKind.warning,
    ko: '고개를 든 렙이 {n}번 있었어. 시선은 손 조금 앞 바닥으로!',
    en: 'You lifted your head on {n} reps. Look at the floor just ahead of your hands!',
  ),
  KoriFeedbackLine(
    key: 'pushup_hand_position',
    kind: KoriFeedbackKind.warning,
    ko: '손은 어깨 바로 아래에 짚어 줘!',
    en: 'Place your hands right under your shoulders!',
  ),
  KoriFeedbackLine(
    key: 'pushup_depth_fade',
    kind: KoriFeedbackKind.warning,
    ko: '뒤로 갈수록 점점 얕아졌어. 깊이를 지킬 수 있는 만큼만 하자!',
    en: 'Your reps got shallower as you went. Only do as many as you can at full depth!',
  ),

  // 스쿼트
  KoriFeedbackLine(
    key: 'squat_hips_first',
    kind: KoriFeedbackKind.warning,
    ko: '잠깐! 엉덩이만 먼저 올라와. 가슴이랑 같이!',
    en: 'Wait! Your hips are rising first. Lift your chest with them!',
  ),
  KoriFeedbackLine(
    key: 'squat_shallow',
    kind: KoriFeedbackKind.warning,
    ko: '이번엔 얕았어! 아까만큼 앉아 줘',
    en: 'That one was shallow! Sit as deep as before',
  ),
  KoriFeedbackLine(
    key: 'squat_no_lockout',
    kind: KoriFeedbackKind.warning,
    ko: '다 안 일어선 렙이 {n}번 있었어. 위에서 무릎이랑 엉덩이를 끝까지 펴 줘.',
    en: "You didn't stand all the way up on {n} reps. Fully extend your knees and hips at the top.",
  ),
  KoriFeedbackLine(
    key: 'squat_lean_drift',
    kind: KoriFeedbackKind.warning,
    ko: '뒤로 갈수록 상체가 점점 숙여졌어. 마지막 렙까지 처음 자세를 지켜 보자.',
    en: 'Your torso leaned further as you went. Keep your starting posture to the last rep.',
  ),
  KoriFeedbackLine(
    key: 'squat_depth_fade',
    kind: KoriFeedbackKind.warning,
    ko: '뒤로 갈수록 점점 얕아졌어.',
    en: 'Your reps got shallower as you went.',
  ),
  KoriFeedbackLine(
    key: 'squat_knee_valgus',
    kind: KoriFeedbackKind.warning,
    ko: '잠깐! 무릎이 안으로 모여. 무릎을 발끝 쪽으로 밀어 줘!',
    en: 'Wait! Your knees are caving in. Push them out toward your toes!',
  ),
  KoriFeedbackLine(
    key: 'squat_heel_rise',
    kind: KoriFeedbackKind.warning,
    ko: '뒤꿈치 떴어! 발 전체로 바닥 눌러 줘',
    en: 'Your heels lifted! Press the floor with your whole foot',
  ),

  // 바벨로우
  KoriFeedbackLine(
    key: 'row_torso_swing',
    kind: KoriFeedbackKind.warning,
    ko: '잠깐! 몸 반동 쓰고 있어. 상체 고정!',
    en: "Wait! You're swinging your body. Keep your torso still!",
  ),
  KoriFeedbackLine(
    key: 'row_standing_up',
    kind: KoriFeedbackKind.warning,
    ko: '몸이 점점 일어서고 있어! 처음처럼 숙여 줘',
    en: "You're standing up more and more! Hinge over like at the start",
  ),
  KoriFeedbackLine(
    key: 'row_short_pull',
    kind: KoriFeedbackKind.warning,
    ko: '끝까지 당겨 줘! 팔꿈치 더 뒤로',
    en: 'Pull all the way! Elbows further back',
  ),
  KoriFeedbackLine(
    key: 'row_head_up',
    kind: KoriFeedbackKind.warning,
    ko: '고개를 든 렙이 {n}번 있었어. 목은 몸이랑 일자로, 시선은 바닥으로!',
    en: 'You lifted your head on {n} reps. Neck in line with your body, eyes on the floor!',
  ),
  KoriFeedbackLine(
    key: 'row_shrug',
    kind: KoriFeedbackKind.warning,
    ko: '어깨가 올라갔어! 어깨 내리고 당겨 줘',
    en: 'Your shoulders went up! Drop them and pull',
  ),

  // 공통
  KoriFeedbackLine(
    key: 'setup_side_view',
    kind: KoriFeedbackKind.setup,
    ko: '옆모습이 보이게 폰을 옆에 둬 줘!',
    en: 'Put your phone to the side so I can see your profile!',
  ),
  KoriFeedbackLine(
    key: 'setup_full_body',
    kind: KoriFeedbackKind.setup,
    ko: '머리부터 발끝까지 다 보이게 서 줘!',
    en: 'Stand so I can see you from head to toe!',
  ),
  KoriFeedbackLine(
    key: 'setup_phone_upright',
    kind: KoriFeedbackKind.setup,
    ko: '폰이 기울었어! 세로로 똑바로 세워 줘',
    en: 'Your phone is tilted! Stand it upright',
  ),
  KoriFeedbackLine(
    key: 'setup_front_view',
    kind: KoriFeedbackKind.setup,
    ko: '이번엔 정면에서 볼게! 폰을 앞에 둬 줘',
    en: "This time I'll watch from the front! Put your phone in front of you",
  ),
  KoriFeedbackLine(
    key: 'tracking_lost',
    kind: KoriFeedbackKind.setup,
    ko: '인식이 잠깐 끊겼어. 그대로 계속해!',
    en: 'I lost track of you for a moment. Keep going!',
  ),
  KoriFeedbackLine(
    key: 'praise_fixed',
    kind: KoriFeedbackKind.praise,
    ko: '좋아, 방금 렙 딱 좋았어!',
    en: 'Nice, that rep was spot on!',
  ),
  KoriFeedbackLine(
    key: 'praise_clean_set',
    kind: KoriFeedbackKind.praise,
    ko: '{reps}개 다 좋았어! 수고했어',
    en: 'All {reps} reps looked great! Nice work',
  ),
  KoriFeedbackLine(
    key: 'set_summary',
    kind: KoriFeedbackKind.setup,
    ko: '수고했어! 고칠 점 {k}개 정리해 뒀어',
    en: "Nice work! I noted {k} things to fix",
  ),
];

final Map<String, KoriFeedbackLine> koriFeedbackLines = {
  for (final line in _lines) line.key: line,
};

/// 네이티브 피드백 연동 전, 렙마다 칭찬과 번갈아 보여줄 운동별 대표 경고.
/// 대사가 아직 없는 운동은 null (칭찬만 보여준다).
const Map<String, String> koriDemoWarningKeyByExercise = {
  'pushup': 'pushup_hip_sag',
  'squat': 'squat_knee_valgus',
  'barbell-row': 'row_torso_swing',
};

/// 리포트 "자주 나온 실수"에 쓰는 경고 키별 짧은 이름 (한국어, 영어).
const Map<String, (String, String)> koriMistakeLabels = {
  'pushup_hip_sag': ('엉덩이 처짐', 'Hips sagging'),
  'pushup_hip_pike': ('엉덩이 들림', 'Hips piking'),
  'pushup_shallow': ('내려가는 깊이 부족', 'Shallow depth'),
  'pushup_no_lockout': ('팔 덜 폄', 'No lockout'),
  'pushup_head_drop': ('고개 떨굼', 'Head dropping'),
  'pushup_head_up': ('고개 듦', 'Head lifted'),
  'pushup_hand_position': ('손 위치', 'Hand position'),
  'pushup_depth_fade': ('갈수록 얕아짐', 'Depth fading'),
  'squat_hips_first': ('엉덩이 먼저 올라옴', 'Hips rising first'),
  'squat_shallow': ('앉는 깊이 부족', 'Shallow depth'),
  'squat_no_lockout': ('덜 일어섬', 'No lockout'),
  'squat_lean_drift': ('상체 점점 숙여짐', 'Torso leaning more'),
  'squat_depth_fade': ('갈수록 얕아짐', 'Depth fading'),
  'squat_knee_valgus': ('무릎 안쪽 모임', 'Knees caving in'),
  'squat_heel_rise': ('뒤꿈치 들림', 'Heels lifting'),
  'row_torso_swing': ('상체 반동', 'Torso swinging'),
  'row_standing_up': ('상체 일어섬', 'Standing up'),
  'row_short_pull': ('당기기 부족', 'Short pull'),
  'row_head_up': ('고개 듦', 'Head lifted'),
  'row_shrug': ('어깨 으쓱', 'Shoulder shrug'),
};

/// 경고 키의 운동 id (키 앞부분 기준). 알 수 없으면 null.
String? koriMistakeExerciseId(String key) {
  if (key.startsWith('pushup_')) return 'pushup';
  if (key.startsWith('squat_')) return 'squat';
  if (key.startsWith('row_')) return 'barbell-row';
  return null;
}
