import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/mock_data.dart';
import '../../../models/workout_record_model.dart';
import '../../home/providers/home_provider.dart';

// 리포트 > 분석 탭 데이터. 종목별 비율과 세션 수는 실제 운동 기록
// (allRecordsProvider)에서 계산한다. "자주 나온 실수"는 기록에 자세 피드백 횟수가
// 아직 저장되지 않아 빈 목록이다 — 백엔드가 기록에 피드백 횟수를 내려주면 여기서
// 집계한다 (백엔드 요청 문서 "요청 1").

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
  return buildReportAnalysis(ref.watch(allRecordsProvider));
});

/// 범례를 위에서 아래로 훑었을 때 색상환을 따라 이어지는 순서
/// (핑크 → 빨강 → 라임 → 민트 → 파랑). 운동마다 색을 고정한다.
const Map<String, Color> _exerciseColors = {
  'squat': AppColors.pink,
  'benchpress': AppColors.red,
  'deadlift': AppColors.green,
  'barbell-row': Color(0xFF47FFCE),
  'pushup': Color(0xFF54BDFF),
};

ReportAnalysisData buildReportAnalysis(List<WorkoutRecordModel> records) {
  final counts = <String, int>{};
  final names = <String, (String, String)>{};
  for (final r in records) {
    counts[r.exerciseId] = (counts[r.exerciseId] ?? 0) + 1;
    final known = mockExercises.where((e) => e.id == r.exerciseId).firstOrNull;
    names[r.exerciseId] = known != null
        ? (known.nameKr, known.name)
        : (r.exerciseName, r.exerciseName);
  }
  final total = records.length;
  final ids = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  final percents = _percentsSummingTo100([for (final id in ids) counts[id]!]);

  final ratios = [
    for (final (i, id) in ids.indexed)
      ExerciseRatioItem(
        labelKo: names[id]!.$1,
        labelEn: names[id]!.$2,
        percent: percents[i],
        color: _exerciseColors[id] ?? AppColors.purple,
      ),
  ];

  final String insightKo;
  final String insightEn;
  if (ratios.isEmpty) {
    insightKo = '운동 기록이 쌓이면\n코리가 분석해 줄게!';
    insightEn = "Once you log some workouts,\nI'll break them down for you!";
  } else {
    final top = ratios.first;
    insightKo = '${top.labelKo}${_objectParticle(top.labelKo)} 가장 많이 했어!\n'
        '전체 운동의 ${top.percent}%야.';
    insightEn = 'You did ${top.labelEn} the most!\n'
        "That's ${top.percent}% of your workouts.";
  }

  return ReportAnalysisData(
    totalSessions: total,
    ratios: ratios,
    mistakes: const [],
    insightKo: insightKo,
    insightEn: insightEn,
  );
}

/// 반올림 오차를 큰 나머지 순으로 나눠 합이 정확히 100이 되게 한다.
List<int> _percentsSummingTo100(List<int> counts) {
  final total = counts.fold<int>(0, (a, c) => a + c);
  if (total == 0) return [for (final _ in counts) 0];
  final exact = [for (final c in counts) c * 100 / total];
  final result = [for (final e in exact) e.floor()];
  var left = 100 - result.fold<int>(0, (a, c) => a + c);
  final order = List.generate(counts.length, (i) => i)
    ..sort((a, b) => (exact[b] - result[b]).compareTo(exact[a] - result[a]));
  for (final i in order) {
    if (left <= 0) break;
    result[i] += 1;
    left -= 1;
  }
  return result;
}

/// 받침이 있으면 '을', 없으면 '를'.
String _objectParticle(String word) {
  if (word.isEmpty) return '를';
  final code = word.codeUnitAt(word.length - 1);
  if (code < 0xAC00 || code > 0xD7A3) return '를';
  return (code - 0xAC00) % 28 == 0 ? '를' : '을';
}
