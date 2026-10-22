import 'package:bpt/features/workout/screens/native_pose_workout_screen.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 소리 끄기 버튼이 실제 코리 음성(bpt/kori_voice)을 끄는지 본다.
/// 카메라 화면은 지원하지 않는 운동으로 띄워 네이티브 뷰 없이 진행한다.
void main() {
  late List<String> voiceCalls;

  setUp(() {
    voiceCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('bpt/kori_voice'),
            (call) async {
      voiceCalls.add(call.method);
      return null;
    });
  });

  Future<void> startLive(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // 아이폰 화면 크기.
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // 테스트 글꼴은 실제보다 커서 휴식 화면 카드가 넘친다. 넘침 경고만 무시한다.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.toString().contains('overflowed')) onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(
        home: NativePoseWorkoutScreen(
            exerciseId: 'test', targetReps: 1, targetSets: 2),
      ),
    ));
    // 자세 안내 1.8초 + 카운트다운 3초.
    await tester.pump(const Duration(milliseconds: 1800));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('set summary is spoken when sound is on', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await startLive(tester);

    await tester.tap(find.text('+1회 (테스트용)'));
    await tester.pump();

    expect(voiceCalls, contains('speak'));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('muting stops the voice and nothing more is spoken',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await startLive(tester);

    await tester.tap(find.byIcon(Icons.volume_up_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(voiceCalls, ['stop']);

    await tester.tap(find.text('+1회 (테스트용)'));
    await tester.pump();

    expect(voiceCalls, isNot(contains('speak')));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
