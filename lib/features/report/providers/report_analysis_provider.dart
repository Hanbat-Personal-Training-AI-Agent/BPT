import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';

// ── ⚠️ MOCK DATA ─────────────────────────────────────────────────────────
// 분석 탭은 아직 운동 종목별 세션 집계와 자세 실수 분류를 만들어 주는 백엔드가
// 없어서(리포트 화면의 운동량 탭과 달리 실제 WorkoutRecordModel에서 계산하지
// 않는다), 화면 레이아웃만 먼저 구현하고 고정된 목데이터를 채워 둔 상태다.
// 특히 "자주 나온 실수" 목록은 실제 자세 평가 로직이 생기면 항목/문구가 통째로
// 바뀔 자리표시자이니, 실 데이터 연동 시 이 파일 전체를 교체한다.

/// 분석 탭 하나의 종목 비율 항목.
class ExerciseRatioItem {
  const ExerciseRatioItem({
    required this.labelKo,
    required this.labelEn,
    required this.percent,
    required this.color,
  });
  final String labelKo;
  final String labelEn;
  final int percent;
  final Color color;

  String label(bool isKo) => isKo ? labelKo : labelEn;
}

/// "자주 나온 실수" 목록 한 항목.
class MistakeItem {
  const MistakeItem({
    required this.labelKo,
    required this.labelEn,
    required this.count,
    required this.color,
  });
  final String labelKo;
  final String labelEn;
  final int count;
  final Color color;

  String label(bool isKo) => isKo ? labelKo : labelEn;
}

class ReportAnalysisData {
  const ReportAnalysisData({
    required this.totalSessions,
    required this.ratios,
    required this.mistakes,
    required this.insightKo,
    required this.insightEn,
  });

  final int totalSessions;
  final List<ExerciseRatioItem> ratios;
  final List<MistakeItem> mistakes;
  final String insightKo;
  final String insightEn;

  int get totalMistakes => mistakes.fold(0, (a, m) => a + m.count);

  String insight(bool isKo) => isKo ? insightKo : insightEn;
}

final reportAnalysisProvider = Provider<ReportAnalysisData>((ref) {
  ref.watch(selectedLanguageProvider); // 언어가 바뀌면 문구도 다시 계산
  return _mockAnalysisData;
});

const _mockAnalysisData = ReportAnalysisData(
  totalSessions: 42,
  // 6종목 합이 정확히 100%가 되도록 맞춘 목데이터. '기타' 항목은 없다.
  ratios: [
    ExerciseRatioItem(
      labelKo: '스쿼트',
      labelEn: 'Squat',
      percent: 30,
      color: AppColors.green,
    ),
    ExerciseRatioItem(
      labelKo: '벤치프레스',
      labelEn: 'Bench Press',
      percent: 22,
      color: AppColors.purple,
    ),
    ExerciseRatioItem(
      labelKo: '데드리프트',
      labelEn: 'Deadlift',
      percent: 17,
      color: AppColors.pink,
    ),
    ExerciseRatioItem(
      labelKo: '바벨로우',
      labelEn: 'Barbell Row',
      percent: 13,
      color: Color(0xFF47FFCE),
    ),
    ExerciseRatioItem(
      labelKo: '푸쉬업',
      labelEn: 'Push Up',
      percent: 10,
      color: Color(0xFF54BDFF),
    ),
    ExerciseRatioItem(
      labelKo: '랫풀다운',
      labelEn: 'Lat Pulldown',
      percent: 8,
      color: AppColors.red,
    ),
  ],
  mistakes: [
    MistakeItem(
      labelKo: '무릎 안쪽 모임',
      labelEn: 'Knees caving in',
      count: 24,
      color: Color(0xFF47FFCE),
    ),
    MistakeItem(
      labelKo: '상체 과도한 숙임',
      labelEn: 'Excessive torso lean',
      count: 17,
      color: AppColors.pink,
    ),
    MistakeItem(
      labelKo: '하강 깊이 부족',
      labelEn: 'Shallow depth',
      count: 13,
      color: AppColors.purple,
    ),
    MistakeItem(
      labelKo: '팔꿈치 벌어짐',
      labelEn: 'Elbows flaring',
      count: 9,
      color: Color(0xFF54BDFF),
    ),
    MistakeItem(
      labelKo: '허리 과신전',
      labelEn: 'Lower back overextension',
      count: 5,
      color: AppColors.green,
    ),
  ],
  insightKo: '하체 운동을 많이 했고, 무릎 정렬 문제가 가장 자주 보였어.\n'
      '다음 달엔 워밍업에 고관절 스트레칭을 하나 추가해보자!',
  insightEn: 'You trained your lower body a lot, and knee alignment was the '
      'most common issue.\nLet\'s add a hip stretch to next month\'s warm-up!',
);
