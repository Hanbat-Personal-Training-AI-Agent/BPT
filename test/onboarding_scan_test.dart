import 'package:bpt/features/onboarding/screens/onboarding_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the first pose, close button and help link on entry',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScanScreen()));

    expect(find.text('1 / 4 · 정면'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('도움말'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the searching-state guidance bubble with no countdown',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScanScreen()));

    expect(find.text('카메라 보고 팔은 A자로,\n발은 어깨너비로 벌려 줘!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('help link opens a tips bottom sheet', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScanScreen()));

    await tester.tap(find.text('도움말'));
    await tester.pumpAndSettle();

    expect(find.text('촬영 팁'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pose chips reflect front-active, others waiting on entry',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScanScreen()));

    expect(find.text('촬영 중'), findsOneWidget);
    expect(find.text('대기 중'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('temporary debug skip button advances to the next pose',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScanScreen()));

    expect(find.text('다음 (테스트용)'), findsOneWidget);

    await tester.tap(find.text('다음 (테스트용)'));
    await tester.pump();

    expect(find.text('2 / 4 · 왼쪽'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
