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
// TODO: 실제 마지막 체형 측정일이 저장되면 그 값에서 계산한 값으로 교체할 것.
// 지금은 두 화면이 같은 목데이터를 보도록 여기 한 곳에서만 관리한다.
const bodyCheckCycleDays = 30;
final daysSinceLastBodyCheckProvider = StateProvider<int>((ref) => 30);

enum BodyCheckState { fresh, dueSoon, overdue }

BodyCheckState resolveBodyCheckState(int daysSinceLastCheck) {
  if (daysSinceLastCheck >= bodyCheckCycleDays) return BodyCheckState.overdue;
  final daysUntilNext =
      (bodyCheckCycleDays - daysSinceLastCheck).clamp(0, bodyCheckCycleDays);
  return daysUntilNext <= 3 ? BodyCheckState.dueSoon : BodyCheckState.fresh;
}

// ── All records ───────────────────────────────────────────────────────────
// 시연용으로 목데이터를 실제 기록과 항상 같이 보여준다. 실제 기록만 보고 싶으면
// false 로 바꾸면 된다 (그때도 실제 기록이 없으면 목데이터를 보여준다).
const showMockWorkoutRecords = true;

final allRecordsProvider = Provider<List<WorkoutRecordModel>>((ref) {
  final recordsAsync = ref.watch(workoutRecordsProvider);
  // 한 회도 세지 못하고 끝난 기록(테스트 중 바로 종료 등)은 목록에서 뺀다.
  final records = (recordsAsync.value ?? [])
      .where((r) => r.totalReps > 0)
      .toList();
  if (records.isEmpty) return mockWorkoutRecords;
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
  };
});

// ── Recommended exercise ──────────────────────────────────────────────────
final recommendedExerciseProvider = Provider<ExerciseModel>(
  (ref) => mockExercises[0],
);
