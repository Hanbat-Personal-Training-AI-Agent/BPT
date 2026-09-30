import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_scaffold.dart';

const _weeklyFrequencyOptions = [2, 3, 4, 5, 6];

/// 신체 정보·목표 입력이 끝났으니 서버에 저장한다. 저장을 기다리지 않고 바로
/// 체형 측정으로 넘어가며, 실패하면 토스트로만 알린다.
Future<void> _saveOnboarding(
    BuildContext context, WidgetRef ref, OnboardingState state) async {
  final auth = ref.read(authNotifierProvider);
  // 서버 계정으로 로그인한 경우에만 저장한다 (오프라인·테스트 로그인은 제외).
  if (!auth.isLoggedIn || auth.isOfflineMode) return;
  final error = await auth.saveOnboarding(
    gender: state.genderCode,
    heightCm: state.heightCm,
    weightKg: state.weightKg,
    workoutGoal: state.goalCode,
    weeklyFrequency: state.weeklyFrequency,
  );
  if (error != null && context.mounted) {
    showAppToast(context, error, type: AppToastType.error);
  }
}

class OnboardingGoalScreen extends ConsumerWidget {
  const OnboardingGoalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    return OnboardingScaffold(
      step: 3,
      totalSteps: 4,
      onBack: () => context.pop(),
      nextLabel: '체형 측정하러 가기',
      onNext: () {
        _saveOnboarding(context, ref, state);
        context.push(RouteConstants.onboardingCapture);
      },
      headline: const Text('목표가 뭐야?\n거기에 맞춰줄게',
          style: TextStyle(
              fontSize: 27,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -1)),
      body: [
        _GoalCard(
          icon: Icons.fitness_center_rounded,
          title: '근력 증가',
          subtitle: '고중량 · 저반복',
          selected: state.goal == WorkoutGoal.strength,
          onTap: () => notifier.selectGoal(WorkoutGoal.strength),
        ),
        const SizedBox(height: 8),
        _GoalCard(
          icon: Icons.trending_down_rounded,
          title: '체중 감량',
          subtitle: '고반복 · 짧은 휴식',
          selected: state.goal == WorkoutGoal.weightLoss,
          onTap: () => notifier.selectGoal(WorkoutGoal.weightLoss),
        ),
        const SizedBox(height: 8),
        _GoalCard(
          icon: Icons.accessibility_new_rounded,
          title: '체형 교정',
          subtitle: '자세 정확도 우선',
          selected: state.goal == WorkoutGoal.postureCorrection,
          onTap: () => notifier.selectGoal(WorkoutGoal.postureCorrection),
        ),
        const SizedBox(height: 8),
        _GoalCard(
          icon: Icons.favorite_rounded,
          title: '건강 관리',
          subtitle: '주 3회 가벼운 루틴',
          selected: state.goal == WorkoutGoal.healthCare,
          onTap: () => notifier.selectGoal(WorkoutGoal.healthCare),
        ),
        const SizedBox(height: 18),
        const Text('일주일에 몇 번 볼까?',
            style: TextStyle(
                color: AppColors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final freq in _weeklyFrequencyOptions) ...[
              if (freq != _weeklyFrequencyOptions.first)
                const SizedBox(width: 8),
              Expanded(
                child: _FrequencyChip(
                  frequency: freq,
                  selected: state.weeklyFrequency == freq,
                  onTap: () => notifier.setWeeklyFrequency(freq),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Image.asset(
              'assets/images/character/face.png',
              width: 62,
              height: 68,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppColors.purple,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
                    bottomRight: Radius.circular(22),
                    bottomLeft: Radius.circular(3),
                  ),
                ),
                child: Text(
                  '주 ${state.weeklyFrequency}회 ${state.goalCourseLabel} 코스로 가볼게!\n'
                  '세트 수량 반복 횟수는 나중에 바꿀 수 있어.',
                  style: const TextStyle(
                      color: AppColors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.4),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.green : AppColors.grey,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected ? AppColors.black : const Color(0xFF2B2B2B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    color: selected ? AppColors.green : AppColors.white,
                    size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: selected ? AppColors.black : AppColors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 1),
                    Text(subtitle,
                        style: TextStyle(
                            color: selected
                                ? const Color(0xFF3F5518)
                                : const Color(0xFF888888),
                            fontSize: 11)),
                  ],
                ),
              ),
              if (selected)
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppColors.black,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: AppColors.green, size: 14),
                ),
            ],
          ),
        ),
      );
}

class _FrequencyChip extends StatelessWidget {
  const _FrequencyChip({
    required this.frequency,
    required this.selected,
    required this.onTap,
  });

  final int frequency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple : AppColors.grey,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text('$frequency',
                  style: TextStyle(
                      color: selected ? AppColors.black : AppColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
              Text('회',
                  style: TextStyle(
                      color: selected
                          ? const Color(0xFF4A2E7A)
                          : const Color(0xFF888888),
                      fontSize: 11)),
            ],
          ),
        ),
      );
}
