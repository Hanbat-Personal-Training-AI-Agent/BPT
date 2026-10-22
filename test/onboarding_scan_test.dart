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

  testWidgets('shows no Kori bubble or hold indicator before the camera reports',
      (tester) async {
    await tester.pumpWidget(_screen());

    expect(find.image(const AssetImage('assets/images/character/face.png')),
        findsNothing);
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

    // 한 줄: 촬영 중인 칸만 상태를 붙이고, 대기 칸은 이름만.
    expect(find.text('정면 촬영 중'), findsOneWidget);
    expect(find.textContaining('대기 중'), findsNothing);
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

  testWidgets('Kori bubble sits at the top in one line, status chips at the bottom',
      (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: CalibrationScanOverlay(
        preview: SizedBox.expand(),
        silhouettes: null,
        guidance: '좋아! 그대로 잠깐만',
        targetView: 'front',
        capturedViews: [],
        holdProgress: 0.5,
        isPassing: true,
        flash: false,
      ),
    ));

    final screenHeight = tester.view.physicalSize.height / 3;
    final bubble = find.text('좋아! 그대로 잠깐만');
    expect(tester.getCenter(bubble).dy, lessThan(screenHeight * 0.25));
    expect(tester.getCenter(find.text('정면 촬영 중')).dy,
        greaterThan(screenHeight * 0.8));
    expect(tester.getSize(bubble).height, lessThan(24)); // 한 줄
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('test capture button shows only when given and calls back',
      (tester) async {
    var finished = 0;
    Widget overlay({VoidCallback? onDebugCapture}) => MaterialApp(
          home: CalibrationScanOverlay(
            preview: const SizedBox.expand(),
            silhouettes: null,
            guidance: null,
            targetView: 'front',
            capturedViews: const [],
            holdProgress: 0,
            isPassing: false,
            flash: false,
            onDebugCapture: onDebugCapture,
          ),
        );

    await tester.pumpWidget(overlay());
    expect(find.textContaining('(테스트용)'), findsNothing);

    await tester.pumpWidget(overlay(onDebugCapture: () => finished++));
    await tester.tap(find.text('정면 촬영 완료 (테스트용)'));
    expect(finished, 1);
  });

  testWidgets('test capture button steps through the views in turn order',
      (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_screen());

    for (final (done, next) in [('정면', '왼쪽'), ('왼쪽', '뒷면'), ('뒷면', '오른쪽')]) {
      await tester.tap(find.text('$done 촬영 완료 (테스트용)'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('$done 완료'), findsOneWidget);
      expect(find.text('$next 촬영 중'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
