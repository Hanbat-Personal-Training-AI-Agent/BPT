import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/account_recovery_screen.dart';
import '../../features/auth/screens/sign_up_screen.dart';
import '../../features/onboarding/screens/onboarding_gender_screen.dart';
import '../../features/onboarding/screens/onboarding_body_screen.dart';
import '../../features/onboarding/screens/onboarding_goal_screen.dart';
import '../../features/onboarding/screens/onboarding_capture_screen.dart';
import '../../features/onboarding/screens/onboarding_scan_screen.dart';
import '../../features/onboarding/screens/onboarding_analyzing_screen.dart';
import '../../features/onboarding/screens/onboarding_result_screen.dart';
import '../../features/calendar/screens/calendar_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/profile/screens/account_info_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/report/screens/report_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/workout/screens/camera_guide_screen.dart';
import '../../features/workout/screens/exercise_selection_screen.dart';
import '../../features/workout/screens/native_pose_workout_screen.dart';
import '../../features/workout/screens/workout_result_screen.dart';
import '../constants/route_constants.dart';
import '../shell/main_shell.dart';

/// 로그인 상태 + 현재 위치만으로 리다이렉트 대상을 결정하는 순수 함수.
/// GoRouter/Firebase 없이 단위 테스트할 수 있도록 분리했다.
String? resolveAuthRedirect(
    {required bool loggedIn, required String location}) {
  if (location == RouteConstants.splash) return null;

  if (!loggedIn &&
      location != RouteConstants.login &&
      location != RouteConstants.accountRecovery &&
      location != RouteConstants.signUp &&
      location != RouteConstants.onboardingGender &&
      location != RouteConstants.onboardingBody &&
      location != RouteConstants.onboardingGoal &&
      location != RouteConstants.onboardingCapture &&
      location != RouteConstants.onboardingScan &&
      location != RouteConstants.onboardingAnalyzing &&
      location != RouteConstants.onboardingResult) {
    return RouteConstants.login;
  }
  if (loggedIn && location == RouteConstants.login) return RouteConstants.home;
  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // ref.read (not watch) so GoRouter is not recreated on auth change.
  // refreshListenable handles dynamic redirects instead.
  final authNotifier = ref.read(authNotifierProvider);

  return GoRouter(
    initialLocation: RouteConstants.splash,
    refreshListenable: authNotifier,
    redirect: (BuildContext context, GoRouterState state) =>
        resolveAuthRedirect(
      loggedIn: authNotifier.isLoggedIn,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: RouteConstants.splash,
        pageBuilder: (context, state) => _fadePage(state, const SplashScreen()),
      ),
      GoRoute(
        path: RouteConstants.login,
        pageBuilder: (context, state) => _fadePage(
          state,
          const LoginScreen(),
        ),
      ),
      GoRoute(
        path: RouteConstants.accountRecovery,
        pageBuilder: (context, state) =>
            _slidePage(state, const AccountRecoveryScreen()),
      ),
      GoRoute(
        path: RouteConstants.signUp,
        pageBuilder: (context, state) =>
            _slidePage(state, const SignUpScreen()),
      ),
      GoRoute(
        path: RouteConstants.onboardingGender,
        pageBuilder: (context, state) =>
            _slidePage(state, const OnboardingGenderScreen()),
      ),
      GoRoute(
        path: RouteConstants.onboardingBody,
        pageBuilder: (context, state) =>
            _slidePage(state, const OnboardingBodyScreen()),
      ),
      GoRoute(
        path: RouteConstants.onboardingGoal,
        pageBuilder: (context, state) =>
            _slidePage(state, const OnboardingGoalScreen()),
      ),
      GoRoute(
        path: RouteConstants.onboardingCapture,
        pageBuilder: (context, state) =>
            _slidePage(state, const OnboardingCaptureScreen()),
      ),
      GoRoute(
        path: RouteConstants.onboardingScan,
        pageBuilder: (context, state) =>
            _slidePage(state, const OnboardingScanScreen()),
      ),
      GoRoute(
        path: RouteConstants.onboardingAnalyzing,
        pageBuilder: (context, state) {
          final scanPaths =
              (state.extra as List?)?.cast<String>() ?? const <String>[];
          return _slidePage(
              state, OnboardingAnalyzingScreen(scanPaths: scanPaths));
        },
      ),
      GoRoute(
        path: RouteConstants.onboardingResult,
        pageBuilder: (context, state) =>
            _slidePage(state, const OnboardingResultScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: RouteConstants.home,
            pageBuilder: (context, state) =>
                _tabPage(state, 0, const HomeScreen()),
          ),
          GoRoute(
            path: RouteConstants.calendar,
            pageBuilder: (context, state) =>
                _tabPage(state, 1, const CalendarScreen()),
          ),
          GoRoute(
            path: RouteConstants.report,
            pageBuilder: (context, state) =>
                _tabPage(state, 3, const ReportScreen()),
          ),
          GoRoute(
            path: RouteConstants.profile,
            pageBuilder: (context, state) =>
                _tabPage(state, 4, const ProfileScreen()),
          ),
          GoRoute(
            path: RouteConstants.exerciseSelection,
            pageBuilder: (context, state) =>
                _tabPage(state, 2, const ExerciseSelectionScreen()),
          ),
        ],
      ),
      GoRoute(
        path: RouteConstants.editProfile,
        pageBuilder: (context, state) =>
            _slidePage(state, const EditProfileScreen()),
      ),
      GoRoute(
        path: RouteConstants.accountInfo,
        pageBuilder: (context, state) =>
            _slidePage(state, const AccountInfoScreen()),
      ),
      GoRoute(
        path: RouteConstants.cameraGuide,
        pageBuilder: (context, state) {
          final extra = state.extra;
          var exerciseId = 'squat';
          var targetReps = 15;
          var targetSets = 3;
          var setWeightsKg = const <int>[];
          var setReps = const <int>[];
          var restSeconds = 60;
          if (extra is Map) {
            exerciseId = extra['exerciseId'] as String? ?? exerciseId;
            targetReps = extra['targetReps'] as int? ?? targetReps;
            targetSets = extra['targetSets'] as int? ?? targetSets;
            setWeightsKg = _intList(extra['setWeightsKg']);
            setReps = _intList(extra['setReps']);
            restSeconds = extra['restSeconds'] as int? ?? restSeconds;
          }
          return _slidePage(
            state,
            CameraGuideScreen(
              exerciseId: exerciseId,
              targetReps: targetReps,
              targetSets: targetSets,
              setWeightsKg: setWeightsKg,
              setReps: setReps,
              restSeconds: restSeconds,
            ),
          );
        },
      ),
      GoRoute(
        path: RouteConstants.nativePoseWorkout,
        pageBuilder: (context, state) {
          final extra = state.extra;
          var exerciseId = 'squat';
          var targetReps = 15;
          var targetSets = 3;
          var setWeightsKg = const <int>[];
          var setReps = const <int>[];
          var restSeconds = 60;
          if (extra is Map) {
            exerciseId = extra['exerciseId'] as String? ?? exerciseId;
            targetReps = extra['targetReps'] as int? ?? targetReps;
            targetSets = extra['targetSets'] as int? ?? targetSets;
            setWeightsKg = _intList(extra['setWeightsKg']);
            setReps = _intList(extra['setReps']);
            restSeconds = extra['restSeconds'] as int? ?? restSeconds;
          } else if (extra is String) {
            exerciseId = extra;
          }
          return _slidePage(
            state,
            NativePoseWorkoutScreen(
              exerciseId: exerciseId,
              targetReps: targetReps,
              targetSets: targetSets,
              setWeightsKg: setWeightsKg,
              setReps: setReps,
              restSeconds: restSeconds,
            ),
          );
        },
      ),
      GoRoute(
        path: RouteConstants.workoutResult,
        pageBuilder: (context, state) {
          final result = state.extra as Map<String, dynamic>? ?? const {};
          return _slidePage(state, WorkoutResultScreen(result: result));
        },
      ),
    ],
  );
});

/// route extra 로 넘어온 세트별 값(무게·반복 수) 목록. 없거나 형식이 다르면 빈 목록.
List<int> _intList(Object? raw) => raw is List
    ? raw.whereType<num>().map((e) => e.toInt()).toList()
    : const <int>[];

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (_, animation, __, c) =>
        FadeTransition(opacity: animation, child: c),
  );
}

CustomTransitionPage<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (_, animation, __, c) {
      final tween = Tween(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: animation.drive(tween), child: c);
    },
  );
}

// ── 하단 탭 전환 ──────────────────────────────────────────────────────────
// 네비바 순서(홈, 캘린더, 운동, 리포트, 프로필)대로 옆으로 밀어서 넘긴다.
// 오른쪽 탭으로 가면 새 화면이 오른쪽에서 들어오고 이전 화면은 왼쪽으로 밀려나며,
// 두 화면이 같은 속도로 붙어서 움직여 한 장처럼 이어진다.
int? _currentTabIndex;

/// 1: 오른쪽 탭으로 이동, -1: 왼쪽 탭으로 이동.
/// 들어오는 화면과 나가는 화면이 같은 값을 읽어야 해서 한 곳에 둔다.
double _tabSlideDirection = 1;

CustomTransitionPage<void> _tabPage(
    GoRouterState state, int tabIndex, Widget child) {
  // pageBuilder 는 같은 화면에서도 다시 불릴 수 있어서, 탭이 실제로 바뀔 때만 방향을 갱신한다.
  final previous = _currentTabIndex;
  if (previous != null && previous != tabIndex) {
    _tabSlideDirection = tabIndex > previous ? 1 : -1;
  }
  _currentTabIndex = tabIndex;

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (_, animation, secondaryAnimation, c) {
      final curve = CurveTween(curve: Curves.easeOutCubic);
      final dir = _tabSlideDirection;
      // 들어올 때: 이동 방향 쪽 바깥에서 가운데로.
      final enter = animation.drive(curve).drive(
            Tween(begin: Offset(dir, 0), end: Offset.zero),
          );
      // 나갈 때: 가운데에서 반대쪽 바깥으로 (다음 화면의 진행에 맞춰 함께 이동).
      final exit = secondaryAnimation.drive(curve).drive(
            Tween(begin: Offset.zero, end: Offset(-dir, 0)),
          );
      return SlideTransition(
        position: exit,
        child: SlideTransition(position: enter, child: c),
      );
    },
  );
}
