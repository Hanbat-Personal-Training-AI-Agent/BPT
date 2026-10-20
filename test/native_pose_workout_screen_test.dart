import 'package:bpt/core/i18n/locale_provider.dart';
import 'package:bpt/features/workout/screens/native_pose_workout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf'));
    await font.load();
  });

  testWidgets('첫 피드백 대사가 오기 전에는 렙이 늘어도 원래 대기 문구를 유지한다(n/목표회 없음)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
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
    expect(find.text('Keep your knees pointed toward your toes'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
