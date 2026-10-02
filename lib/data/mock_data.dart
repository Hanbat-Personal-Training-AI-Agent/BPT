import 'dart:math';

import 'package:flutter/material.dart' show Color;

import '../models/exercise_model.dart';
import '../models/user_model.dart';
import '../models/workout_record_model.dart';

// ── Mock User ──────────────────────────────────────────────────────────────
final mockUser = UserModel(
  id: 'u001',
  username: 'jinjeong',
  name: 'Jin Jeong',
  email: 'jinjeong619@gmail.com',
  password: '',
  avatarInitials: 'JJ',
  birthDate: DateTime(2001, 3, 15),
  weightKg: 70,
  heightCm: 175,
  totalWorkouts: 48,
  streakDays: 7,
  joinedAt: DateTime(2025, 1, 15),
);

// ── Mock Exercises ─────────────────────────────────────────────────────────
final mockExercises = <ExerciseModel>[
  const ExerciseModel(
    id: 'squat',
    name: 'Squat',
    nameKr: '스쿼트',
    description: 'Compound lower-body movement targeting quads & glutes.',
    imagePath: 'assets/images/squat.png',
    type: ExerciseType.reps,
    defaultReps: 15,
    defaultSets: 3,
    defaultDurationSeconds: 0,
    targetMuscles: ['Quads', 'Glutes', 'Hamstrings'],
    difficulty: DifficultyLevel.beginner,
    accentColor: Color(0xFF00C6AE),
  ),
  const ExerciseModel(
    id: 'benchpress',
    name: 'Bench Press',
    nameKr: '벤치프레스',
    description: 'Classic chest press building pectoral strength.',
    imagePath: 'assets/images/benchpress.png',
    type: ExerciseType.reps,
    defaultReps: 10,
    defaultSets: 3,
    defaultDurationSeconds: 0,
    targetMuscles: ['Chest', 'Shoulders', 'Triceps'],
    difficulty: DifficultyLevel.intermediate,
    accentColor: Color(0xFFFF6B35),
  ),
  const ExerciseModel(
    id: 'deadlift',
    name: 'Deadlift',
    nameKr: '데드리프트',
    description: 'Full-body pull building posterior chain strength.',
    imagePath: 'assets/images/deadlift.png',
    type: ExerciseType.reps,
    defaultReps: 8,
    defaultSets: 3,
    defaultDurationSeconds: 0,
    targetMuscles: ['Back', 'Glutes', 'Hamstrings'],
    difficulty: DifficultyLevel.advanced,
    accentColor: Color(0xFFEF4444),
  ),
  const ExerciseModel(
    id: 'barbell-row',
    name: 'Barbell Row',
    nameKr: '바벨로우',
    description: 'Back and posterior-chain pulling exercise using a barbell.',
    imagePath: 'assets/images/row.png',
    type: ExerciseType.reps,
    defaultReps: 12,
    defaultSets: 3,
    defaultDurationSeconds: 0,
    targetMuscles: ['Back', 'Lats', 'Rear Delts', 'Biceps'],
    difficulty: DifficultyLevel.intermediate,
    accentColor: Color(0xFF3B82F6),
  ),
  const ExerciseModel(
    id: 'pushup',
    name: 'Push-up',
    nameKr: '푸쉬업',
    description: 'Upper-body push targeting chest, shoulders & triceps.',
    imagePath: 'assets/images/pushup.png',
    type: ExerciseType.reps,
    defaultReps: 12,
    defaultSets: 3,
    defaultDurationSeconds: 0,
    targetMuscles: ['Chest', 'Shoulders', 'Triceps'],
    difficulty: DifficultyLevel.beginner,
    accentColor: Color(0xFFF59E0B),
    usesWeight: false,
  ),
  const ExerciseModel(
    id: 'lat-pulldown',
    name: 'Lat Pulldown',
    nameKr: '랫풀다운',
    description: 'Back-focused pulling exercise using a cable machine.',
    imagePath: 'assets/images/lat-pulldown.png',
    type: ExerciseType.reps,
    defaultReps: 12,
    defaultSets: 3,
    defaultDurationSeconds: 0,
    targetMuscles: ['Back', 'Lats', 'Biceps'],
    difficulty: DifficultyLevel.beginner,
    accentColor: Color(0xFF8B5CF6),
  ),
];

ExerciseModel findExercise(String id) =>
    mockExercises.firstWhere((e) => e.id == id, orElse: () => mockExercises[0]);

// 무게 트래킹 필드가 아직 모델/백엔드에 없어서, 화면 표시용 목데이터로만 사용.
const mockWeightKgByExercise = <String, int>{
  'squat': 60,
  'benchpress': 45,
  'deadlift': 80,
  'barbell-row': 40,
  'pushup': 0,
};

// ── Mock Workout Records ───────────────────────────────────────────────────
// 실제로 운동한 것처럼 보이도록 오늘 기준 최근 약 6개월치 기록을 생성한다.
// 시드를 고정해 앱을 켤 때마다 같은 기록이 나오고, 날짜만 오늘 기준으로 이동한다.
// - 주 3~4회 (월·수·금 위주, 가끔 화·목·토), 평일 저녁 / 주말 낮
// - 분할 루틴(하체+가슴 / 등 / 가슴+맨몸)을 번갈아 수행
// - 기간이 지날수록 무게·자세 점수가 조금씩 오름
// - totalReps 는 실제 기록과 같이 "전체 세트 합계"
final mockWorkoutRecords = _buildMockWorkoutRecords();

class _MockPlan {
  const _MockPlan({
    required this.name,
    required this.sets,
    required this.repsPerSet,
    required this.startKg,
    required this.endKg,
    required this.secPerRep,
  });
  final String name;
  final int sets;
  final int repsPerSet;
  final double startKg;
  final double endKg;
  final int secPerRep;
}

const _mockPlans = <String, _MockPlan>{
  'squat': _MockPlan(
      name: 'Squat', sets: 4, repsPerSet: 10, startKg: 50, endKg: 60, secPerRep: 4),
  'benchpress': _MockPlan(
      name: 'Bench Press', sets: 4, repsPerSet: 8, startKg: 35, endKg: 45, secPerRep: 4),
  'deadlift': _MockPlan(
      name: 'Deadlift', sets: 3, repsPerSet: 5, startKg: 65, endKg: 80, secPerRep: 5),
  'barbell-row': _MockPlan(
      name: 'Barbell Row', sets: 3, repsPerSet: 10, startKg: 30, endKg: 40, secPerRep: 3),
  'pushup': _MockPlan(
      name: 'Push-up', sets: 3, repsPerSet: 15, startKg: 0, endKg: 0, secPerRep: 2),
};

// 분할 루틴: 운동한 날마다 순서대로 돌아간다.
const _mockRoutines = [
  ['squat', 'benchpress'],
  ['deadlift', 'barbell-row'],
  ['benchpress', 'pushup'],
  ['squat', 'barbell-row', 'pushup'],
];

const _mockGoodNotes = <String, List<String>>{
  'squat': ['깊이 아주 좋았어! 허벅지가 바닥과 평행까지 잘 내려갔어.', '무릎이랑 발끝 방향이 끝까지 잘 맞았어.'],
  'benchpress': ['바가 가슴 같은 위치에 꾸준히 닿았어. 궤적이 안정적이야!', '견갑 고정이 잘 됐어. 이대로만 가자!'],
  'deadlift': ['허리가 끝까지 중립으로 잘 유지됐어!', '바가 몸에 붙어서 잘 올라왔어.'],
  'barbell-row': ['상체 각도가 흔들리지 않고 잘 버텼어!', '팔꿈치를 뒤로 잘 당겼어. 등 자극 좋았을 거야.'],
  'pushup': ['몸통이 일자로 잘 유지됐어!', '가동 범위 끝까지 잘 내려갔어.'],
};

const _mockFixNotes = <String, List<String>>{
  'squat': ['마지막 세트에서 무릎이 안쪽으로 살짝 모였어.', '올라올 때 엉덩이가 먼저 뜨는 반복이 있었어.'],
  'benchpress': ['후반 세트에서 엉덩이가 벤치에서 살짝 떴어.', '내릴 때 속도가 조금 빨랐어. 천천히 컨트롤해보자.'],
  'deadlift': ['마지막 반복에서 허리가 살짝 말렸어.', '시작할 때 바가 몸에서 조금 떨어졌어.'],
  'barbell-row': ['반동을 써서 당기는 반복이 몇 번 있었어.', '후반에 상체가 점점 세워졌어.'],
  'pushup': ['후반 세트에서 허리가 조금 처졌어.', '팔꿈치가 옆으로 많이 벌어졌어.'],
};

List<WorkoutRecordModel> _buildMockWorkoutRecords() {
  const spanDays = 180;
  final rng = Random(20260930);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // 요일별 운동 확률 (월=1 … 일=7)
  const dayChance = {1: 0.85, 2: 0.25, 3: 0.8, 4: 0.25, 5: 0.75, 6: 0.45, 7: 0.1};

  final records = <WorkoutRecordModel>[];
  var routineIndex = 0;

  // 오늘 기록은 만들지 않는다. 오늘 운동 여부는 실제 기록으로만 판단해야
  // 이번 주 목표/오늘 요약에 하지 않은 운동이 잡히지 않는다.
  for (var offset = spanDays; offset >= 1; offset--) {
    final day = today.subtract(Duration(days: offset));
    final roll = rng.nextDouble();
    if (roll > dayChance[day.weekday]!) continue;

    // 시작 시각: 평일 저녁 18:40~21:00, 주말 10:00~15:00.
    DateTime start;
    if (day.weekday >= 6) {
      start = day.add(Duration(hours: 10, minutes: rng.nextInt(300)));
    } else {
      start = day.add(Duration(hours: 18, minutes: 40 + rng.nextInt(140)));
    }

    // 진행도(0 → 1): 무게와 자세 점수가 점점 좋아진다.
    final progress = 1 - offset / spanDays;
    final routine = _mockRoutines[routineIndex % _mockRoutines.length];
    routineIndex++;

    var cursor = start;
    for (var i = 0; i < routine.length; i++) {
      final id = routine[i];
      final plan = _mockPlans[id]!;
      final targetReps = plan.sets * plan.repsPerSet;
      final missed = rng.nextDouble() < 0.25 ? 1 + rng.nextInt(2) : 0;
      final totalReps = targetReps - missed;
      final badRate = 0.18 - 0.12 * progress + rng.nextDouble() * 0.06;
      // 가끔은 자세 지적 없이 깔끔하게 끝난 날도 있다.
      final incorrect = rng.nextDouble() < 0.2
          ? 0
          : (totalReps * badRate).round().clamp(0, totalReps);
      final correct = totalReps - incorrect;
      final score =
          (correct / totalReps * 100 - rng.nextDouble() * 4).clamp(60.0, 99.0);
      // 5kg 단위로 반올림한 점진적 증량 (결과 화면이 정수 kg 로 표시하므로)
      final rawKg = plan.startKg + (plan.endKg - plan.startKg) * progress;
      final weightKg = (rawKg / 5).round() * 5.0;
      final restSec = 90 + rng.nextInt(60);
      final duration =
          totalReps * plan.secPerRep + (plan.sets - 1) * restSec + 30;

      final good = _mockGoodNotes[id]!;
      final fix = _mockFixNotes[id]!;
      records.add(WorkoutRecordModel(
        id: 'mock-${day.year}${day.month.toString().padLeft(2, '0')}'
            '${day.day.toString().padLeft(2, '0')}-$i',
        exerciseId: id,
        exerciseName: plan.name,
        date: cursor,
        weightKg: weightKg,
        totalReps: totalReps,
        correctReps: correct,
        incorrectReps: incorrect,
        durationSeconds: duration,
        postureScore: double.parse(score.toStringAsFixed(1)),
        feedbackNotes: incorrect == 0
            ? [good[rng.nextInt(good.length)]]
            : [fix[rng.nextInt(fix.length)], good[rng.nextInt(good.length)]],
        targetReps: targetReps,
        targetSets: plan.sets,
        isSynced: true,
      ));
      // 다음 운동은 기구 정리·이동 시간(3~7분) 뒤에 시작
      cursor = cursor.add(Duration(seconds: duration, minutes: 3 + rng.nextInt(5)));
    }
  }

  // 화면들은 최신 기록이 앞에 오는 순서를 기대한다.
  records.sort((a, b) => b.date.compareTo(a.date));
  return records;
}

// ── Chart Mock Data ────────────────────────────────────────────────────────
final dailyPostureScores = [78.0, 82.0, 80.0, 85.0, 88.0, 84.0, 92.0];
final weeklyReps = [45.0, 60.0, 38.0, 72.0, 55.0, 80.0, 68.0];
final monthlyWorkoutMinutes = [
  120.0,
  90.0,
  150.0,
  200.0,
  175.0,
  220.0,
  190.0,
  240.0,
  210.0,
  180.0,
  230.0,
  260.0
];

// Real-time feedback pool
const workoutFeedbacks = [
  'Great form! Keep going!',
  'Keep your back straight',
  'Lower your hips more',
  'Perfect depth!',
  'Control your descent',
  'Excellent posture!',
  'Engage your core',
  'Eyes forward',
  'Breathe out on the way up',
  'Full range of motion!',
];
