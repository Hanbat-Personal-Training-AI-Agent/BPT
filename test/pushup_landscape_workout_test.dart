import 'dart:io';

import 'package:bpt/features/workout/screens/native_pose_workout_screen.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 푸쉬업 운동 화면을 가로(아이폰 15 크기)로 띄워 운동 중 → 쉬는 시간 → 운동 끝까지
/// 화면이 넘치지 않는지, 결과 화면으로 갈 때 세로로 돌리는지 본다.
/// 실제 앱 글꼴(Pretendard)로 그려야 넘침을 제대로 볼 수 있다.
Future<void> _loadPretendard() async {
  final loader = FontLoader('Pretendard');
  for (final w in [
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
    'Black'
  ]) {
    final bytes = File('assets/fonts/Pretendard-$w.otf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  late List<Object?> orientations;

  setUpAll(_loadPretendard);

  setUp(() {
    orientations = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientations.add(call.arguments);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('bpt/kori_voice'), (_) async => null);
  });

  // 아이폰 15(노치 있음)와 가장 작은 아이폰 SE.
  for (final (name, size, notch) in [
    ('iPhone 15', const Size(852, 393), 59.0),
    ('iPhone SE', const Size(667, 375), 0.0),
  ]) {
    testWidgets('push-up workout fits a landscape $name through the whole flow',
        (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = FakeViewPadding(left: notch * 3, right: notch * 3);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(initialLocation: '/workout', routes: [
        GoRoute(
            path: '/workout',
            builder: (_, __) => const NativePoseWorkoutScreen(
                exerciseId: 'pushup', targetReps: 1, targetSets: 2)),
        GoRoute(
            path: '/workout-result',
            builder: (_, __) => const Scaffold(body: Text('result'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(
          theme: ThemeData(fontFamily: 'Pretendard'),
          routerConfig: router,
        ),
      ));

      // 자세 안내 → 카운트다운 → 운동 중.
      await tester.pump(const Duration(milliseconds: 1800));
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('REPS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // 운동명·시간 박스 바로 오른쪽에 소리 버튼, 그 아래에 가로로 긴 REPS,
      // SET 은 오른쪽 끝.
      final timeBox =
          tester.getRect(find.textContaining(RegExp(r'^\d\d:\d\d$')));
      final sound = tester.getRect(find.byIcon(Icons.volume_up_rounded));
      final reps = tester.getRect(find.text('REPS'));
      expect(sound.left, greaterThan(timeBox.right));
      expect(sound.left - timeBox.right, lessThan(40));
      expect(reps.top, greaterThan(sound.bottom));
      final repsCard = tester.getRect(find
          .ancestor(of: find.text('REPS'), matching: find.byType(Container))
          .first);
      expect(repsCard.width, greaterThan(repsCard.height));
      expect(
          tester.getRect(find.text('SET')).left, greaterThan(size.width / 2));

      // 끝내기 확인 창.
      await tester.tap(find.text('끝내기'));
      await tester.pumpAndSettle();
      expect(find.text('벌써 끝낼 거야?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('계속하기'));
      await tester.pumpAndSettle();

      // 1세트 끝 → 쉬는 시간.
      await tester.tap(find.text('+1회 (테스트용)'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('숨 좀 돌리자!'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 2세트 끝 → 운동 끝.
      await tester.tap(find.text('2세트 시작'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('+1회 (테스트용)'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('운동 끝! 해냈다!'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 결과 화면으로 갈 때 세로로 돌린다.
      await tester.tap(find.text('결과 보러 가기'));
      await tester.pump();
      expect(orientations.last, [
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
      ]);
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
