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
  testWidgets('shows the first pose, close button and help link on entry',
      (tester) async {
    await tester.pumpWidget(_screen());

    expect(find.text('1 / 4 · 정면'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('도움말'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the per-view hint and no hold indicator before the camera reports',
      (tester) async {
    await tester.pumpWidget(_screen());

    expect(find.text('카메라 보고 팔은 A자로,\n발은 어깨너비로 벌려 줘!'), findsOneWidget);
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

  testWidgets('pose chips follow the turn order with front active, others waiting',
      (tester) async {
    await tester.pumpWidget(_screen());

    expect(find.text('촬영 중'), findsOneWidget);
    expect(find.text('대기 중'), findsNWidgets(3));
    final labels = ['왼쪽', '뒷면', '오른쪽'].map(find.text);
    for (final label in labels) {
      expect(label, findsOneWidget);
    }
    // Left turn first, then the back, then the right: one continuous turn.
    expect(tester.getTopLeft(find.text('왼쪽')).dx,
        lessThan(tester.getTopLeft(find.text('뒷면')).dx));
    expect(tester.getTopLeft(find.text('뒷면')).dx,
        lessThan(tester.getTopLeft(find.text('오른쪽')).dx));
    expect(tester.takeException(), isNull);
  });
}
