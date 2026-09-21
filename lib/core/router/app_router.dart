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
import '../../features/profile/screens/profile_screen.dart';
import '../../features/report/screens/report_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/workout/screens/camera_guide_screen.dart';
import '../../features/workout/screens/exercise_selection_screen.dart';
import '../../features/workout/screens/native_pose_workout_screen.dart';
import '../../features/workout/screens/workout_result_screen.dart';
import '../../features/workout/screens/workout_screen.dart';
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
                _fadePage(state, const HomeScreen()),
          ),
          GoRoute(
            path: RouteConstants.calendar,
            pageBuilder: (context, state) =>
                _fadePage(state, const CalendarScreen()),
          ),
          GoRoute(
            path: RouteConstants.report,
            pageBuilder: (context, state) =>
                _fadePage(state, const ReportScreen()),
          ),
          GoRoute(
            path: RouteConstants.profile,
            pageBuilder: (context, state) =>
                _fadePage(state, const ProfileScreen()),
          ),
          GoRoute(
            path: RouteConstants.exerciseSelection,
            pageBuilder: (context, state) =>
                _fadePage(state, const ExerciseSelectionScreen()),
          ),
        ],
      ),
      GoRoute(
        path: RouteConstants.cameraGuide,
        pageBuilder: (context, state) {
          final extra = state.extra;
          var exerciseId = 'squat';
          var targetReps = 15;
          var targetSets = 3;
          if (extra is Map) {
            exerciseId = extra['exerciseId'] as String? ?? exerciseId;
            targetReps = extra['targetReps'] as int? ?? targetReps;
            targetSets = extra['targetSets'] as int? ?? targetSets;
          }
          return _slidePage(
            state,
            CameraGuideScreen(
              exerciseId: exerciseId,
              targetReps: targetReps,
              targetSets: targetSets,
            ),
          );
        },
      ),
      GoRoute(
        path: RouteConstants.workout,
        pageBuilder: (context, state) {
          final exerciseId = state.extra as String? ?? 'squat';
          return _slidePage(state, WorkoutScreen(exerciseId: exerciseId));
        },
      ),
      GoRoute(
        path: RouteConstants.nativePoseWorkout,
        pageBuilder: (context, state) {
          final extra = state.extra;
          var exerciseId = 'squat';
          var targetReps = 15;
          var targetSets = 3;
          if (extra is Map) {
            exerciseId = extra['exerciseId'] as String? ?? exerciseId;
            targetReps = extra['targetReps'] as int? ?? targetReps;
            targetSets = extra['targetSets'] as int? ?? targetSets;
          } else if (extra is String) {
            exerciseId = extra;
          }
          return _slidePage(
            state,
            NativePoseWorkoutScreen(
              exerciseId: exerciseId,
              targetReps: targetReps,
              targetSets: targetSets,
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
