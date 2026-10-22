import 'package:bpt/features/workout/screens/camera_guide_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Object?> orientations;

  setUp(() {
    orientations = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientations.add(call.arguments);
      }
      return null;
    });
  });

  Future<void> show(WidgetTester tester, String exerciseId, Size size) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: CameraGuideScreen(
            exerciseId: exerciseId, targetReps: 10, targetSets: 3),
      ),
    ));
  }

  testWidgets('push-up guide turns landscape and asks for a horizontal phone',
      (tester) async {
    await show(tester, 'pushup', const Size(852, 393));

    expect(orientations.single, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    expect(find.text('폰은 가로로, 거치대에 고정해줘'), findsOneWidget);
    expect(find.text('도움말'), findsNothing);
    // 가로 배치: 그림은 왼쪽, 설명과 시작 버튼은 오른쪽.
    final image = find
        .image(const AssetImage('assets/images/character/camera_pushup.png'));
    expect(tester.getCenter(image).dx,
        lessThan(tester.getTopLeft(find.text('끝! 시작할게')).dx));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    expect(orientations.last, [
      'DeviceOrientation.portraitUp',
      'DeviceOrientation.portraitDown',
    ]);
  });

  testWidgets('other exercises stay portrait with a vertical phone',
      (tester) async {
    await show(tester, 'squat', const Size(393, 852));

    expect(orientations, isEmpty);
    expect(find.text('폰은 세로로, 거치대에 고정해줘'), findsOneWidget);
    expect(find.text('도움말'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
