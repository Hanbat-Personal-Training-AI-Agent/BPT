import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../models/workout_record_model.dart';
import '../../../services/workout_records_service.dart';

/// 리포트 상단 탭 (운동량 / 분석).
enum ReportSection { volume, analysis }

/// 운동량 탭의 집계 단위 (일별 / 주별 / 월별).
enum ReportPeriod { daily, weekly, monthly }

final reportSectionProvider =
    StateProvider<ReportSection>((ref) => ReportSection.volume);

final reportPeriodProvider =
    StateProvider<ReportPeriod>((ref) => ReportPeriod.weekly);

/// 차트에 그리는 구간 수: 지난 6개 구간 + 현재 구간.
const reportBucketCount = 7;

/// 마지막으로 끝난 구간의 인덱스 (현재 구간 바로 앞).
const reportLastCompletedIndex = reportBucketCount - 2;

/// 현재(진행 중) 구간의 인덱스.
const reportCurrentIndex = reportBucketCount - 1;

/// 운동량 탭에 표시할 집계 결과. 모든 합계는 차트에 보이는 7개 구간 전체 기준이다.
class ReportVolumeData {
  const ReportVolumeData({
    required this.period,
    required this.labels,
    required this.minutes,
    required this.reps,
    required this.totalSeconds,
    required this.totalReps,
    required this.activeDays,
    required this.timeChangePct,
  });

  final ReportPeriod period;
  final List<String> labels;

  /// 구간별 운동 시간(분).
  final List<double> minutes;

  /// 구간별 반복 횟수.
  final List<double> reps;

  final int totalSeconds;
  final int totalReps;

  /// 운동 기록이 있는 날짜 수(중복 제거).
  final int activeDays;

  /// 마지막으로 끝난 구간의 운동 시간이 그 전 구간 대비 몇 % 변했는지.
  /// 비교할 이전 기록이 없으면 null.
  final int? timeChangePct;

  bool get hasData => totalSeconds > 0 || totalReps > 0;

  /// 운동한 날 하루당 평균 반복 횟수.
  int get avgRepsPerActiveDay =>
      activeDays == 0 ? 0 : (totalReps / activeDays).round();
}

final reportVolumeProvider = Provider<ReportVolumeData>((ref) {
  final period = ref.watch(reportPeriodProvider);
  final records = ref.watch(workoutRecordsProvider).value ?? const [];
  final isKo = ref.watch(selectedLanguageProvider) == 'ko';
  return buildReportVolume(records, period, isKo: isKo, now: DateTime.now());
});

const _weekdayKo = ['월', '화', '수', '목', '금', '토', '일'];
const _weekdayEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// [now] 기준으로 지난 6개 구간 + 현재 구간을 [period] 단위로 집계한다.
ReportVolumeData buildReportVolume(
  List<WorkoutRecordModel> records,
  ReportPeriod period, {
  required bool isKo,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final currentMonday = DateTime(today.year, today.month, today.day - (today.weekday - 1));

  // 구간 i(0=가장 오래된 구간, 6=현재)의 [시작, 끝) 범위. DateTime 생성자의
  // 날짜 오버플로 보정을 이용해 월/연도 경계와 서머타임을 안전하게 넘는다.
  DateTime startOf(int i) {
    final back = reportCurrentIndex - i;
    switch (period) {
      case ReportPeriod.daily:
        return DateTime(today.year, today.month, today.day - back);
      case ReportPeriod.weekly:
        return DateTime(currentMonday.year, currentMonday.month,
            currentMonday.day - back * 7);
      case ReportPeriod.monthly:
        return DateTime(today.year, today.month - back);
    }
  }

  DateTime endOf(int i) {
    final s = startOf(i);
    switch (period) {
      case ReportPeriod.daily:
        return DateTime(s.year, s.month, s.day + 1);
      case ReportPeriod.weekly:
        return DateTime(s.year, s.month, s.day + 7);
      case ReportPeriod.monthly:
        return DateTime(s.year, s.month + 1);
    }
  }

  String labelOf(int i) {
    if (i == reportCurrentIndex) {
      if (period == ReportPeriod.daily) return isKo ? '오늘' : 'Today';
      return isKo ? '이번' : 'Now';
    }
    switch (period) {
      case ReportPeriod.daily:
        final wd = startOf(i).weekday - 1;
        return isKo ? _weekdayKo[wd] : _weekdayEn[wd];
      case ReportPeriod.weekly:
        return isKo ? '${i + 1}주' : 'W${i + 1}';
      case ReportPeriod.monthly:
        final m = startOf(i).month;
        return isKo ? '$m월' : _monthEn[m - 1];
    }
  }

  final minutes = List<double>.filled(reportBucketCount, 0);
  final reps = List<double>.filled(reportBucketCount, 0);
  final activeDates = <DateTime>{};
  var totalSeconds = 0;
  var totalReps = 0;

  for (var i = 0; i < reportBucketCount; i++) {
    final start = startOf(i);
    final end = endOf(i);
    for (final r in records) {
      if (r.date.isBefore(start) || !r.date.isBefore(end)) continue;
      minutes[i] += r.durationSeconds / 60.0;
      reps[i] += r.totalReps;
      totalSeconds += r.durationSeconds;
      totalReps += r.totalReps;
      activeDates.add(DateTime(r.date.year, r.date.month, r.date.day));
    }
  }

  final prior = minutes[reportLastCompletedIndex - 1];
  final last = minutes[reportLastCompletedIndex];
  final int? changePct = prior > 0 ? ((last - prior) / prior * 100).round() : null;

  return ReportVolumeData(
    period: period,
    labels: List.generate(reportBucketCount, labelOf),
    minutes: minutes,
    reps: reps,
    totalSeconds: totalSeconds,
    totalReps: totalReps,
    activeDays: activeDates.length,
    timeChangePct: changePct,
  );
}
