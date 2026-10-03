// Renders the real calibration capture UI, frame by frame, from a replayed session.
//
// Inputs (see outputs/app_mock/, produced from calibration-replay):
//   states.json  per-frame engine state (bubble line, target view, captured views, hold…)
//   bg/####.png  the camera frame for each state, already mirrored like the front preview
// Output: frames/####.png at iPhone 17 size (393×852 pt @2x), then the analysis screen
// the app navigates to after the last capture.
//
//   flutter test tool/calibration_mock_video_test.dart
//
// Lives outside test/ so the normal `flutter test` run does not pick it up.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;


import 'package:bpt/features/onboarding/screens/onboarding_analyzing_screen.dart';
import 'package:bpt/features/onboarding/screens/onboarding_scan_screen.dart';
import 'package:bpt/features/onboarding/widgets/calibration_silhouette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _mockDir = 'outputs/app_mock';
const _logical = Size(393, 852);
const _pixelRatio = 2.0;
const _analysisSeconds = 3;

Future<void> _loadFonts() async {
  final pretendard = FontLoader('Pretendard');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    pretendard.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
  }
  await pretendard.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
      .load();
}

void main() {
  testWidgets('render the calibration mock frames', (tester) async {
    final states = (jsonDecode(File('$_mockDir/states.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final out = Directory('$_mockDir/frames')..createSync(recursive: true);
    for (final old in out.listSync()) {
      old.deleteSync();
    }

    tester.view.physicalSize = _logical * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    tester.view.padding = const FakeViewPadding(top: 59 * _pixelRatio, bottom: 34 * _pixelRatio);
    tester.view.viewPadding = const FakeViewPadding(top: 59 * _pixelRatio, bottom: 34 * _pixelRatio);
    addTearDown(tester.view.reset);

    await tester.runAsync(_loadFonts);
    final silhouettes = (await tester.runAsync(CalibrationSilhouettes.load))!;
    final boundaryKey = GlobalKey();
    var frame = 0;

    Future<void> capture() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: _pixelRatio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File('${out.path}/${(frame++).toString().padLeft(4, '0')}.png').writeAsBytesSync(png!);
    }

    Widget app(Widget home) => RepaintBoundary(
          key: boundaryKey,
          child: ProviderScope(
            child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark(), home: home),
          ),
        );

    for (final state in states) {
      final background = MemoryImage(
          File('$_mockDir/bg/${(state['i'] as int).toString().padLeft(4, '0')}.png').readAsBytesSync());
      await tester.pumpWidget(app(CalibrationScanOverlay(
        preview: Image(image: background, fit: BoxFit.cover, gaplessPlayback: true),
        silhouettes: silhouettes,
        guidance: state['shown'] as String?,
        targetView: state['target'] as String?,
        capturedViews: (state['captured'] as List).cast<String>(),
        holdProgress: (state['hold'] as num).toDouble(),
        isPassing: state['pass'] as bool,
        flash: state['flash'] as bool,
      )));
      final context = boundaryKey.currentContext!;
      await tester.runAsync(() => Future.wait([
            precacheImage(background, context),
            precacheImage(const AssetImage('assets/images/character/face.png'), context),
          ]));
      await tester.pump(const Duration(milliseconds: 40));  // 25 fps, so the flash fades in real time
      await capture();
    }

    // After the fourth view the app goes straight to the analysis screen.
    await tester.pumpWidget(app(const OnboardingAnalyzingScreen(sessionPath: '/mock/session')));
    for (var i = 0; i < _analysisSeconds * 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await capture();
    }
    // The analysis screen keeps a 40 s timer; stop the clock before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 30)));
}
