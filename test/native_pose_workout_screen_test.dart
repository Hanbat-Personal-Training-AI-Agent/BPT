import 'package:bpt/core/i18n/locale_provider.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bpt/features/workout/screens/workout_result_screen.dart';
import 'package:bpt/features/workout/screens/native_pose_workout_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/features/workout/data/workout_evidence.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SharedPreferences prefs;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final font = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf'));
    await font.load();
  });

  testWidgets('첫 피드백 대사가 오기 전에는 렙이 늘어도 원래 대기 문구를 유지한다(n/목표회 없음)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        home: const NativePoseWorkoutScreen(
          exerciseId: 'squat',
          targetReps: 15,
          setReps: [8],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('준비되면 시작해보자!'), findsOneWidget);
    expect(find.text('무릎이 발끝 방향을 향하게 해줘'), findsOneWidget);

    await tester.tap(find.text('+1회 (테스트용)'));
    await tester.pump();

    expect(find.text('준비되면 시작해보자!'), findsOneWidget);
    expect(find.textContaining('자세 확인 중'), findsNothing);
    expect(find.text('무릎이 발끝 방향을 향하게 해줘'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NativePoseWorkoutScreen)),
    );
    container.read(selectedLanguageProvider.notifier).state = 'en';
    await tester.tap(find.text('+1회 (테스트용)'));
    await tester.pump();

    expect(find.text("Start whenever you're ready!"), findsOneWidget);
    expect(find.textContaining('Checking your form'), findsNothing);
    expect(
        find.text('Keep your knees pointed toward your toes'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final isKo in [true, false]) {
    testWidgets(
        'unassessed reps finish with neutral completion (${isKo ? 'ko' : 'en'})',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'Pretendard'),
          home: const NativePoseWorkoutScreen(
            exerciseId: 'squat',
            targetReps: 2,
            targetSets: 2,
            setReps: [2, 2],
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump(const Duration(seconds: 3));
      final container = ProviderScope.containerOf(
          tester.element(find.byType(NativePoseWorkoutScreen)));
      container.read(selectedLanguageProvider.notifier).state =
          isKo ? 'ko' : 'en';
      await tester.pump();
      // Rep count only: no native posture observation, warning, or assessment event is supplied.
      await tester.tap(find.text('+1회 (테스트용)'));
      await tester.pump();
      await tester.tap(find.text('+1회 (테스트용)'));
      await tester.pump();
      final completed = find.text(isKo ? '완료' : 'Completed');
      expect(completed, findsOneWidget);
      expect(tester.widget<Text>(completed).style?.color,
          Colors.white.withValues(alpha: 0.65));
      expect(find.text(isKo ? '2회 완료!' : '2 reps completed!'), findsOneWidget);
      expect(find.textContaining(isKo ? '완벽' : 'Perfect'), findsNothing);
      expect(find.textContaining(isKo ? '교정' : 'Fix x'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final warningCount in [0, 1]) {
    testWidgets(
        'persisted warning counts are not posture labels ($warningCount)',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'Pretendard'),
          home: WorkoutResultScreen(result: {
            'isHistory': true, // Read-only: no save/network operation.
            'exerciseId': 'squat', 'totalReps': 2,
            'correctReps': 2 - warningCount, 'incorrectReps': warningCount,
            'targetSets': 1,
            'targetReps': warningCount == 0 ? 2 : 4,
            'setResults': [
              {'reps': 2, 'weightKg': 0, 'badCount': warningCount}
            ],
          }),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('전체 자세 판정: 미확인'), findsOneWidget);
      if (warningCount == 0) {
        expect(find.text('목표 횟수 완료!'), findsOneWidget);
        final completed = find.text('완료');
        expect(completed, findsOneWidget);
        expect(tester.widget<Text>(completed).style?.color,
            Colors.white.withValues(alpha: 0.65));
        expect(find.textContaining('기록된 경고는 없어.'), findsOneWidget);
      } else {
        expect(find.text('목표 횟수 50% 완료'), findsOneWidget);
        expect(find.textContaining('1세트에 경고가 기록됐어.'), findsOneWidget);
        expect(find.text('경고 1회'), findsOneWidget);
        expect(find.text('무릎 1회'), findsNothing);
        expect(find.textContaining('안쪽으로'), findsNothing);
        expect(find.textContaining('깊이랑 속도는 좋았어'), findsNothing);
      }
      expect(find.text('안정'), findsNothing);
      expect(find.textContaining('자세 다 좋았어'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'ending after one partial set preserves three planned sets separately',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? sent;
    final router = GoRouter(initialLocation: '/exercise', routes: [
      GoRoute(
          path: '/exercise',
          builder: (_, __) => const NativePoseWorkoutScreen(
              exerciseId: 'squat',
              targetReps: 2,
              targetSets: 3,
              setReps: [2, 2, 2],
              setWeightsKg: [10, 10, 10])),
      GoRoute(
          path: '/workout-result',
          builder: (_, state) {
            sent = (state.extra as Map).cast<String, dynamic>();
            return const Scaffold(body: Text('captured result'));
          }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(
            theme: ThemeData(fontFamily: 'Pretendard'), routerConfig: router)));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('+1회 (테스트용)'));
    await tester.pump();
    await tester.tap(find.text('끝내기'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('끝내기')));
    await tester.pumpAndSettle();
    expect(find.text('captured result'), findsOneWidget);
    expect(sent?['targetSets'], 3);
    expect(sent?['targetReps'], 6);
    expect(sent?['totalReps'], 1);
    final dto = WorkoutMetadataRequestDto.fromJson(sent!);
    expect(dto.totalSets, 1);
    expect(dto.totalVolume, 10);
    expect(WorkoutEvidence.details(dto.poseMetricsSummary)?['formAssessment'],
        'not_available');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
