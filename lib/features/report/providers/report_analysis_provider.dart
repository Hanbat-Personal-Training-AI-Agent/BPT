import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/mock_data.dart';
import '../../../models/workout_record_model.dart';
import '../../home/providers/home_provider.dart';
import '../../workout/data/kori_feedback_lines.dart';

// 리포트 > 분석 탭 데이터. 종목별 비율, 세션 수, "자주 나온 실수"를 모두 실제 운동
// 기록(allRecordsProvider)에서 계산한다. 실수는 기록의 feedbackCounts(네이티브 자세
// 판정이 보낸 경고 횟수)를 키별로 더한 것이다.

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
    this.key,
  });
  final String labelKo;
  final String labelEn;
  final int count;
  final Color color;

  /// 자세 피드백 키 (kori_feedback_lines.dart).
  final String? key;

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

/// "자주 나온 실수" 막대 색. 위에서부터 이 순서로 돌려 쓴다.
const List<Color> _mistakeColors = [
  Color(0xFF47FFCE),
  AppColors.pink,
  AppColors.purple,
  Color(0xFF54BDFF),
  AppColors.green,
];

/// 실수 목록에 보여줄 최대 줄 수.
const int _maxMistakes = 5;

List<MistakeItem> _buildMistakes(List<WorkoutRecordModel> records) {
  final counts = <String, int>{};
  for (final r in records) {
    r.feedbackCounts.forEach((key, count) {
      if (count > 0 && koriMistakeLabels.containsKey(key)) {
        counts[key] = (counts[key] ?? 0) + count;
      }
    });
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return [
    for (final (i, key) in keys.take(_maxMistakes).indexed)
      () {
        final (ko, en) = koriMistakeLabels[key]!;
        final exercise = mockExercises
            .where((e) => e.id == koriMistakeExerciseId(key))
            .firstOrNull;
        return MistakeItem(
          labelKo: exercise == null ? ko : '$ko · ${exercise.nameKr}',
          labelEn: exercise == null ? en : '$en · ${exercise.name}',
          count: counts[key]!,
          color: _mistakeColors[i % _mistakeColors.length],
          key: key,
        );
      }(),
  ];
}

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

  final mistakes = _buildMistakes(records);

  final String insightKo;
  final String insightEn;
  if (ratios.isEmpty) {
    insightKo = '운동 기록이 쌓이면\n코리가 분석해 줄게!';
    insightEn = "Once you log some workouts,\nI'll break them down for you!";
  } else if (mistakes.isNotEmpty) {
    final top = ratios.first;
    final (mistakeKo, mistakeEn) = koriMistakeLabels[mistakes.first.key]!;
    insightKo = '${top.labelKo}${_objectParticle(top.labelKo)} 가장 많이 했고,\n'
        '$mistakeKo${_subjectParticle(mistakeKo)} 가장 자주 보였어.';
    insightEn = 'You did ${top.labelEn} the most,\n'
        'and "$mistakeEn" showed up most often.';
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
    mistakes: mistakes,
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

/// 받침이 있으면 '이', 없으면 '가'.
String _subjectParticle(String word) {
  if (word.isEmpty) return '가';
  final code = word.codeUnitAt(word.length - 1);
  if (code < 0xAC00 || code > 0xD7A3) return '가';
  return (code - 0xAC00) % 28 == 0 ? '가' : '이';
}

/// 받침이 있으면 '을', 없으면 '를'.
String _objectParticle(String word) {
  if (word.isEmpty) return '를';
  final code = word.codeUnitAt(word.length - 1);
  if (code < 0xAC00 || code > 0xD7A3) return '를';
  return (code - 0xAC00) % 28 == 0 ? '를' : '을';
}
