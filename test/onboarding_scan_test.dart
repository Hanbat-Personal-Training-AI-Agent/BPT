import 'package:bpt/features/onboarding/screens/onboarding_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The capture itself is native (camera + RTMPose + judging engine); these cover the
/// overlay this screen owns before any native event arrives.
Widget _screen() => const ProviderScope(
      child: MaterialApp(home: OnboardingScanScreen()),
    );

void main() {
  testWidgets('shows the first target view, close button and help link on entry',
      (tester) async {
    await tester.pumpWidget(_screen());

    expect(find.text('0 / 4 · 정면'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('도움말'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts on the native guidance line with no hold indicator',
      (tester) async {
    await tester.pumpWidget(_screen());

    expect(find.text('화면 안으로 들어와 주세요'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('help link opens a tips bottom sheet', (tester) async {
    await tester.pumpWidget(_screen());

    await tester.tap(find.text('도움말'));
    await tester.pumpAndSettle();

    expect(find.text('촬영 팁'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view chips show front active and the other three waiting',
      (tester) async {
    await tester.pumpWidget(_screen());

    expect(find.text('촬영 중'), findsOneWidget);
    expect(find.text('대기 중'), findsNWidgets(3));
    expect(find.text('뒷면'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
