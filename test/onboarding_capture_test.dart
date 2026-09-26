import 'package:bpt/features/onboarding/screens/onboarding_capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping a pose step switches the preview image', (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: OnboardingCaptureScreen()));

    bool showsAsset(String assetName) => tester
        .widgetList<Image>(find.byType(Image))
        .any((img) => (img.image as AssetImage).assetName == assetName);

    // Defaults to front.
    expect(showsAsset('assets/images/character/front.png'), isTrue);

    await tester.tap(find.text('왼쪽 측면'));
    await tester.pump();
    expect(showsAsset('assets/images/character/left.png'), isTrue);
    expect(showsAsset('assets/images/character/front.png'), isFalse);

    await tester.tap(find.text('오른쪽 측면'));
    await tester.pump();
    expect(showsAsset('assets/images/character/right.png'), isTrue);
    expect(showsAsset('assets/images/character/left.png'), isFalse);

    expect(tester.takeException(), isNull);
  });

  testWidgets('next button is enabled and labeled for the camera step',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingCaptureScreen()));

    final nextFinder = find.widgetWithText(ElevatedButton, '카메라 켜기');
    expect(nextFinder, findsOneWidget);
    expect(tester.widget<ElevatedButton>(nextFinder).onPressed, isNotNull);
  });

  testWidgets('headline stays fixed while the guide content scrolls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: OnboardingCaptureScreen()));

    final headlineBefore =
        tester.getTopLeft(find.text('마지막이야!\n네 방향만 찍으면 끝이야'));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    final headlineAfter = tester.getTopLeft(find.text('마지막이야!\n네 방향만 찍으면 끝이야'));

    expect(headlineAfter, headlineBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('everything fits on a typical phone screen without scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844); // iPhone 14-ish
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: OnboardingCaptureScreen()));
    await tester.pump();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, 0);
  });
}
