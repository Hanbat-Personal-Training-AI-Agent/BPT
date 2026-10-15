import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/mock_data.dart';
import '../../../models/workout_record_model.dart';
import '../../../services/report_service.dart';
import '../../../services/workout_records_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../home/providers/home_provider.dart';
import '../../workout/data/kori_feedback_lines.dart';

// 리포트 > 분석 탭 데이터. 종목별 세션 수와 "자주 나온 실수" 횟수는 서버 집계
// (GET /reports/analysis)를 쓰고, 받기 전이거나 연결이 안 되면 실제 운동
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

/// 서버 분석 집계 (전체 기간). 운동 기록이 바뀌면 다시 받는다.
/// 로그인 전이거나 연결이 안 되면 null.
final serverReportCountsProvider =
    FutureProvider<ReportAnalysisCounts?>((ref) async {
  ref.watch(workoutRecordsProvider);
  if (ref.watch(authNotifierProvider).currentUser == null) return null;
  try {
    return await ref.watch(reportServiceProvider).fetchAnalysis();
  } catch (_) {
    return null;
  }
});

final reportAnalysisProvider = Provider<ReportAnalysisData>((ref) {
  ref.watch(selectedLanguageProvider); // 언어가 바뀌면 문구도 다시 계산
  final server = ref.watch(serverReportCountsProvider).valueOrNull;
  if (server != null) return buildReportAnalysisFromCounts(server);
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

List<MistakeItem> _buildMistakes(Map<String, int> allCounts) {
  final counts = {
    for (final e in allCounts.entries)
      if (e.value > 0 && koriMistakeLabels.containsKey(e.key)) e.key: e.value,
  };
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

/// 기기에 있는 운동 기록으로 분석 탭 데이터를 만든다 (서버 집계를 못 받았을 때).
ReportAnalysisData buildReportAnalysis(List<WorkoutRecordModel> records) {
  final sessions = <String, int>{};
  final names = <String, String>{};
  final mistakes = <String, int>{};
  for (final r in records) {
    sessions[r.exerciseId] = (sessions[r.exerciseId] ?? 0) + 1;
    names[r.exerciseId] = r.exerciseName;
    r.feedbackCounts.forEach((key, count) {
      if (count > 0) mistakes[key] = (mistakes[key] ?? 0) + count;
    });
  }
  return buildReportAnalysisFromCounts(
    ReportAnalysisCounts(
      totalSessions: records.length,
      sessionsByExercise: sessions,
      mistakeCounts: mistakes,
    ),
    exerciseNames: names,
  );
}

/// 종목별 세션 수·실수 횟수로 분석 탭 데이터를 만든다.
/// [exerciseNames]: 앱에 없는 종목 id 일 때 대신 보여줄 이름.
ReportAnalysisData buildReportAnalysisFromCounts(
  ReportAnalysisCounts data, {
  Map<String, String> exerciseNames = const {},
}) {
  final counts = data.sessionsByExercise;
  final names = <String, (String, String)>{};
  for (final id in counts.keys) {
    final known = mockExercises.where((e) => e.id == id).firstOrNull;
    final fallback = exerciseNames[id] ?? id;
    names[id] =
        known != null ? (known.nameKr, known.name) : (fallback, fallback);
  }
  final total = data.totalSessions;
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

  final mistakes = _buildMistakes(data.mistakeCounts);

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
