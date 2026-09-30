import 'package:flutter_riverpod/flutter_riverpod.dart';

enum Gender { male, female, preferNotToSay }

enum BmiCategory { underweight, normal, overweight, obese }

enum WorkoutGoal { strength, weightLoss, postureCorrection, healthCare }

class OnboardingState {
  const OnboardingState({
    this.gender,
    this.heightCm = 176,
    this.weightKg = 71.5,
    this.goal = WorkoutGoal.strength,
    this.weeklyFrequency = 5,
  });

  final Gender? gender;
  final double heightCm;
  final double weightKg;
  final WorkoutGoal goal;
  final int weeklyFrequency;

  /// weight(kg) / height(m)^2
  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  BmiCategory get bmiCategory {
    if (bmi < 18.5) return BmiCategory.underweight;
    if (bmi < 23) return BmiCategory.normal;
    if (bmi < 25) return BmiCategory.overweight;
    return BmiCategory.obese;
  }

  String get bmiCategoryLabel => switch (bmiCategory) {
        BmiCategory.underweight => '저체중',
        BmiCategory.normal => '정상 범위',
        BmiCategory.overweight => '과체중',
        BmiCategory.obese => '비만',
      };

  String get goalCourseLabel => switch (goal) {
        WorkoutGoal.strength => '근력',
        WorkoutGoal.weightLoss => '체중 감량',
        WorkoutGoal.postureCorrection => '체형 교정',
        WorkoutGoal.healthCare => '건강 관리',
      };

  /// 백엔드로 보낼 성별 값 (MALE / FEMALE / NOT_SPECIFIED)
  String get genderCode => switch (gender) {
        Gender.male => 'MALE',
        Gender.female => 'FEMALE',
        Gender.preferNotToSay || null => 'NOT_SPECIFIED',
      };

  /// 백엔드로 보낼 운동 목표 값
  String get goalCode => switch (goal) {
        WorkoutGoal.strength => 'STRENGTH',
        WorkoutGoal.weightLoss => 'WEIGHT_LOSS',
        WorkoutGoal.postureCorrection => 'POSTURE_CORRECTION',
        WorkoutGoal.healthCare => 'HEALTH_CARE',
      };

  OnboardingState copyWith({
    Gender? gender,
    double? heightCm,
    double? weightKg,
    WorkoutGoal? goal,
    int? weeklyFrequency,
  }) =>
      OnboardingState(
        gender: gender ?? this.gender,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        goal: goal ?? this.goal,
        weeklyFrequency: weeklyFrequency ?? this.weeklyFrequency,
      );
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier() : super(const OnboardingState());

  void selectGender(Gender gender) => state = state.copyWith(gender: gender);

  void setHeight(double heightCm) => state = state.copyWith(heightCm: heightCm);

  void setWeight(double weightKg) => state = state.copyWith(weightKg: weightKg);

  void selectGoal(WorkoutGoal goal) => state = state.copyWith(goal: goal);

  void setWeeklyFrequency(int frequency) =>
      state = state.copyWith(weeklyFrequency: frequency);
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
  (ref) => OnboardingNotifier(),
);
