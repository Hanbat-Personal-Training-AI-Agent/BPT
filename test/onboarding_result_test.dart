import 'package:bpt/features/onboarding/screens/onboarding_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'shows the done chips, drag hint, and home button without crashing',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: OnboardingResultScreen()));

    expect(find.text('측정 끝!'), findsOneWidget);
    expect(find.text('드래그해서 360° 돌려봐'), findsOneWidget);
    expect(find.text('완료'), findsNWidgets(4));
    expect(find.widgetWithText(ElevatedButton, '홈으로 가기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the skeleton updates its rotation without crashing',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: OnboardingResultScreen()));

    await tester.drag(find.byType(CustomPaint).last, const Offset(80, 0));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
