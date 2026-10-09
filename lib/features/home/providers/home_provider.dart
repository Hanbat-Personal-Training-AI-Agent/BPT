import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/mock_data.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../models/exercise_model.dart';
import '../../../models/user_model.dart';
import '../../../models/workout_record_model.dart';
import '../../../services/workout_records_service.dart';

// ── Current user (auth first, mock fallback) ──────────────────────────────
final currentUserProvider = Provider<UserModel>((ref) {
  return ref.watch(authNotifierProvider).currentUser ?? mockUser;
});

// ── Weekly goal (user-adjustable, in-memory) ──────────────────────────────
/// 주간 운동 목표(주 N회). 사용자 정보의 weeklyFrequency 를 쓰고, 아직 없으면
/// 서버 기본값과 같은 3회.
final weeklyWorkoutGoalProvider = Provider<int>(
  (ref) => ref.watch(currentUserProvider).weeklyFrequency ?? 3,
);

// ── 체형 재측정 주기 (홈 배너/프로필 카드가 공유하는 상태) ────────────────
// 서버의 마지막 체형 측정일(lastBodyScanDate)에서 계산한다. 한 번도 측정하지
// 않았으면 바로 측정이 필요한 상태(주기만큼 지난 것)로 본다.
const bodyCheckCycleDays = 30;
final daysSinceLastBodyCheckProvider = Provider<int>((ref) {
  final last = ref.watch(currentUserProvider).lastBodyScanDate;
  if (last == null) return bodyCheckCycleDays;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(last.year, last.month, last.day);
  return today.difference(day).inDays.clamp(0, 9999);
});

enum BodyCheckState { fresh, dueSoon, overdue }

BodyCheckState resolveBodyCheckState(int daysSinceLastCheck) {
  if (daysSinceLastCheck >= bodyCheckCycleDays) return BodyCheckState.overdue;
  final daysUntilNext =
      (bodyCheckCycleDays - daysSinceLastCheck).clamp(0, bodyCheckCycleDays);
  return daysUntilNext <= 3 ? BodyCheckState.dueSoon : BodyCheckState.fresh;
}

// ── All records ───────────────────────────────────────────────────────────
// 시연할 때만 true 로 바꾸면 목데이터를 실제 기록과 같이 보여준다.
const showMockWorkoutRecords = false;

final allRecordsProvider = Provider<List<WorkoutRecordModel>>((ref) {
  final recordsAsync = ref.watch(workoutRecordsProvider);
  // 한 회도 세지 못하고 끝난 기록(테스트 중 바로 종료 등)은 목록에서 뺀다.
  final records =
      (recordsAsync.value ?? []).where((r) => r.totalReps > 0).toList();
  if (!showMockWorkoutRecords) return records;
  // 화면들은 최신 기록이 앞에 오는 순서를 기대한다.
  return [...records, ...mockWorkoutRecords]
    ..sort((a, b) => b.date.compareTo(a.date));
});

// ── Recent 3 records ──────────────────────────────────────────────────────
final recentRecordsProvider = Provider<List<WorkoutRecordModel>>((ref) {
  final records = ref.watch(allRecordsProvider);
  return records.take(3).toList();
});

// ── Weekly workout count ──────────────────────────────────────────────────
// 주간 목표는 "주 N회(일)" 기준이라, 기록 개수가 아니라 이번 주에 운동한 날 수를 센다.
// 하루에 여러 종목/여러 번 운동해도 1회로 친다.
final weeklyWorkoutsProvider = Provider<int>((ref) {
  final records = ref.watch(allRecordsProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: now.weekday - 1));
  final weekEnd = today.add(const Duration(days: 1));
  return records
      .map((r) => DateTime(r.date.year, r.date.month, r.date.day))
      .where((d) => !d.isBefore(weekStart) && d.isBefore(weekEnd))
      .toSet()
      .length;
});

// ── Streak days (consecutive days with at least one workout) ──────────────
final streakDaysProvider = Provider<int>((ref) {
  final records = ref.watch(allRecordsProvider);
  if (records.isEmpty) return 0;

  DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  final today = dateOnly(DateTime.now());
  final uniqueDays = records.map((r) => dateOnly(r.date)).toSet().toList()
    ..sort((a, b) => b.compareTo(a));

  final diff = today.difference(uniqueDays.first).inDays;
  if (diff > 1) return 0;

  int streak = 1;
  for (int i = 1; i < uniqueDays.length; i++) {
    final expected = uniqueDays[i - 1].subtract(const Duration(days: 1));
    if (uniqueDays[i] == expected) {
      streak++;
    } else {
      break;
    }
  }
  return streak;
});

// ── Today's summary ───────────────────────────────────────────────────────
// 테스트용: 오늘 실제 기록이 없을 때 홈 상단 통계 카드(운동 시간/완료 세트/총 반복)에
// 보여줄 숫자. 숫자 올라가는 애니메이션을 확인할 때만 true 로 바꾼다.
const showMockTodayStats = false;
const _mockTodayStats = {
  'totalMinutes': 42,
  'completedSets': 8,
  'totalReps': 86,
};

final todaySummaryProvider = Provider<Map<String, dynamic>>((ref) {
  final records = ref.watch(allRecordsProvider);
  final streak = ref.watch(streakDaysProvider);

  final today = DateTime.now();
  final todayRecords = records.where((r) {
    return r.date.year == today.year &&
        r.date.month == today.month &&
        r.date.day == today.day;
  }).toList();

  final totalReps = todayRecords.fold(0, (sum, r) => sum + r.totalReps);
  final totalSecs = todayRecords.fold(0, (sum, r) => sum + r.durationSeconds);
  final completedSets = todayRecords.fold(0, (sum, r) => sum + r.targetSets);
  final avgScore = todayRecords.isEmpty
      ? 0.0
      : todayRecords.fold(0.0, (sum, r) => sum + r.postureScore) /
          todayRecords.length;

  return {
    'workoutsToday': todayRecords.length,
    'totalReps': totalReps,
    'totalMinutes': totalSecs ~/ 60,
    'completedSets': completedSets,
    'avgPostureScore': avgScore,
    'streak': streak,
    if (showMockTodayStats && todayRecords.isEmpty) ..._mockTodayStats,
  };
});

// ── Recommended exercise ──────────────────────────────────────────────────
final recommendedExerciseProvider = Provider<ExerciseModel>(
  (ref) => mockExercises[0],
);

// ── 운동별 시작 무게 ─────────────────────────────────────────────────────────
// 그 운동을 마지막으로 했을 때 든 무게. 기록이 없으면 운동별 기본 무게.
final defaultWeightKgProvider = Provider.family<int, String>((ref, exerciseId) {
  final records = ref.watch(allRecordsProvider);
  WorkoutRecordModel? latest;
  for (final r in records) {
    if (r.exerciseId != exerciseId || r.weightKg <= 0) continue;
    if (latest == null || r.date.isAfter(latest.date)) latest = r;
  }
  if (latest != null) return latest.weightKg.round();
  return mockWeightKgByExercise[exerciseId] ?? 20;
});
