import 'dart:async';

import 'package:bpt/features/onboarding/models/body_analysis_result.dart';
import 'package:bpt/features/onboarding/screens/onboarding_mesh_screen.dart';
import 'package:bpt/features/onboarding/widgets/body_mesh_reveal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  const channel = MethodChannel('bpt/body_mesh');

  testWidgets('native parse failure returns a placeholder result',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'mesh_format'));
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect(await BodyMeshReveal.prepare(Uint8List(0)), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native preparation is bounded and releases a late mesh',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final ready = Completer<String>();
    String? released;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'prepare') return ready.future;
      if (call.method == 'release') {
        released = (call.arguments as Map)['meshId'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final result = BodyMeshReveal.prepare(Uint8List(0));
    await tester.pump(const Duration(seconds: 11));
    expect(await result, isNull);
    ready.complete('late-box');
    await tester.pump();
    expect(released, 'late-box');
    debugDefaultTargetPlatformOverride = null;
  });

  test('summary uses available segments and never invents missing values', () {
    const result = BodyAnalysisResult(values: {
      'userHeightCm': 170,
      'boneLengthData': {
        'unit': 'cm',
        'segments': {
          'shoulder_width': 28,
          'left_shoulder-left_elbow': 26.5,
          'left_elbow-left_wrist': 24.5,
          'right_shoulder-right_elbow': 26.5,
          'left_hip-left_knee': 44,
          'left_knee-left_ankle': 42,
          'pelvis-spine': 24,
          'spine-thorax': 24,
        },
      },
    });
    expect(result.summary, {
      '키': '170.0 cm',
      '어깨 너비': '28.0 cm',
      '왼쪽 팔 길이': '51.0 cm',
      '왼쪽 다리 길이': '86.0 cm',
      '몸통 길이': '48.0 cm',
    });
    expect(const BodyAnalysisResult(values: {'weightKg': 70}).summary,
        {'몸무게': '70.0 kg'});
  });

  test('summary omits invalid values and unknown bone units', () {
    const result = BodyAnalysisResult(values: {
      'userHeightCm': double.nan,
      'weightKg': -1,
      'boneLengthData': {
        'unit': 'm',
        'segments': {'shoulder_width': 0.4}
      },
    });
    expect(result.summary, isEmpty);
  });

  for (final height in [667.0, 844.0]) {
    testWidgets(
        'missing mesh retains summary and continues directly home ($height)',
        (tester) async {
      tester.view.physicalSize = Size(390, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(initialLocation: '/result', routes: [
        GoRoute(
            path: '/result',
            builder: (_, __) => const OnboardingMeshScreen(
                  analysis: BodyAnalysisResult(values: {'userHeightCm': 170}),
                )),
        GoRoute(
            path: '/home', builder: (_, __) => const Scaffold(body: Text('홈'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('신체분석 완료!'), findsOneWidget);
      expect(find.byIcon(Icons.accessibility_new_rounded), findsOneWidget);
      expect(find.text('170.0 cm'), findsOneWidget);
      expect(find.text('몸무게'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('넘어가기'));
      await tester.pumpAndSettle();
      expect(find.text('홈'), findsOneWidget);
    });
  }
}
