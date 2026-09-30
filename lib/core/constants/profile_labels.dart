/// 서버에 저장되는 성별·운동 목표 코드와 화면에 보여줄 한글 이름.
///
/// 값은 항상 서버 코드로 저장하고, 화면에 그릴 때만 [genderLabel] /
/// [goalLabel]로 바꾼다. 예전에 한글 이름으로 저장된 값(예: '여성', '근력 증가')도
/// [normalizeGender] / [normalizeGoal]이 코드로 바꿔 준다.
library;

const genderCodes = ['MALE', 'FEMALE'];

const goalCodes = [
  'STRENGTH',
  'WEIGHT_LOSS',
  'POSTURE_CORRECTION',
  'HEALTH_CARE',
];

const _genderLabels = {
  'MALE': '남성',
  'FEMALE': '여성',
  'NOT_SPECIFIED': '선택 안 함',
};

const _goalLabels = {
  'STRENGTH': '근력 증가',
  'WEIGHT_LOSS': '체중 감량',
  'POSTURE_CORRECTION': '체형 교정',
  'HEALTH_CARE': '건강 관리',
};

// 예전 한글 저장값 → 코드
const _legacyGender = {'남성': 'MALE', '여성': 'FEMALE'};
const _legacyGoal = {
  '근력 증가': 'STRENGTH',
  '근력': 'STRENGTH',
  '체중 감량': 'WEIGHT_LOSS',
  '체형 교정': 'POSTURE_CORRECTION',
  '건강 관리': 'HEALTH_CARE',
};

String? normalizeGender(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final v = value.trim();
  return _legacyGender[v] ?? v.toUpperCase();
}

String? normalizeGoal(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final v = value.trim();
  return _legacyGoal[v] ?? v.toUpperCase();
}

/// 모르는 코드는 그대로 보여준다(서버가 새 값을 추가해도 화면이 비지 않게).
String genderLabel(String? value) {
  final code = normalizeGender(value);
  if (code == null) return '-';
  return _genderLabels[code] ?? value!;
}

String goalLabel(String? value) {
  final code = normalizeGoal(value);
  if (code == null) return '-';
  return _goalLabels[code] ?? value!;
}
