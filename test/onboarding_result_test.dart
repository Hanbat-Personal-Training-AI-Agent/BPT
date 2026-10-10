import 'package:bpt/features/onboarding/screens/onboarding_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rest-pose H36M joints shaped like a server result (metres, x = person's left, y up).
final _positions = [
  [0.0, 0.0, 0.0],
  [-0.15, -0.0, 0.0],
  [-0.11, -0.43, 0.0],
  [-0.11, -0.84, -0.05],
  [0.14, 0.0, 0.0],
  [0.11, -0.44, 0.0],
  [0.1, -0.84, -0.05],
  [0.0, 0.24, 0.0],
  [0.0, 0.48, 0.0],
  [0.0, 0.56, 0.05],
  [0.0, 0.66, 0.0],
  [0.14, 0.45, 0.0],
  [0.41, 0.45, 0.0],
  [0.66, 0.43, 0.0],
  [-0.14, 0.45, 0.0],
  [-0.41, 0.44, 0.0],
  [-0.66, 0.42, 0.0],
];
final _result = <String, dynamic>{
  'stub': false,
  'jointsH36m': {'positions': _positions},
  'coachComment': '허벅지가 키에 비해 긴 편이야.',
};

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('a real result shows the 3D joints, chips, comment and home',
      (tester) async {
    phone(tester);
    await tester
        .pumpWidget(MaterialApp(home: OnboardingResultScreen(result: _result)));
    expect(find.text('측정 끝!'), findsOneWidget);
    expect(find.byKey(const Key('body-3d')), findsOneWidget);
    expect(find.text('드래그해서 360° 돌려봐'), findsOneWidget);
    expect(find.text('완료'), findsNWidgets(4));
    expect(find.text('허벅지가 키에 비해 긴 편이야.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '홈으로 가기'), findsOneWidget);
    await tester.drag(find.byKey(const Key('body-3d')), const Offset(80, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a result no body is drawn (no demo skeleton)',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(const MaterialApp(home: OnboardingResultScreen()));
    expect(find.text('체형 결과 없음'), findsOneWidget);
    expect(find.byKey(const Key('body-3d')), findsNothing);
    expect(find.text('완료'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, '홈으로 가기'), findsOneWidget);
  });

  test('stub or malformed results are rejected', () {
    expect(BodyJoints.fromResult({..._result, 'stub': true}), isNull);
    expect(
        BodyJoints.fromResult({
          'stub': false,
          'jointsH36m': {'positions': _positions.sublist(1)}
        }),
        isNull);
    expect(BodyJoints.fromResult(_result), isNotNull);
  });

  test('projection is real 3D: a quarter turn swaps width for depth', () {
    final joints = BodyJoints.fromResult(_result)!;
    const size = Size(200, 400);
    final front = joints.project(0, size);
    final side = joints.project(1.5707963267948966, size);
    // Left wrist (x = +0.66, z = 0) is far right of the centre facing the camera
    // (the person's left is the viewer's right), and on the centre line side-on.
    expect(front[13].dx - 100, greaterThan(50));
    expect((side[13].dx - 100).abs(), lessThan(1));
    // Turning does not change heights; feet stay at the same baseline.
    expect(side[3].dy, closeTo(front[3].dy, 1e-9));
    expect(front[10].dy, lessThan(front[0].dy)); // head above pelvis
  });
}
