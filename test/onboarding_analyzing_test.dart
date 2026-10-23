import 'dart:async';

import 'package:bpt/features/onboarding/models/body_analysis_result.dart';
import 'package:bpt/features/onboarding/screens/onboarding_analyzing_screen.dart';
import 'package:bpt/features/onboarding/services/calibration_upload_service.dart';
import 'package:bpt/features/onboarding/widgets/body_mesh_reveal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Uploader extends CalibrationUploadService {
  _Uploader({bool configured = true})
      : super(
            config: configured
                ? const CalibrationUploadConfig(
                    apiBaseUrl: 'https://api.example.test',
                    storageHosts: ['photos.example.test'],
                  )
                : const CalibrationUploadConfig(),
            tokenProvider: () async => 'token');
  int calls = 0;
  String? path;
  final result = Completer<CalibrationUploadReceipt>();
  int polls = 0;
  int downloads = 0;
  CalibrationJob job = const CalibrationJob('done', 100);
  bool failDownload = false;

  @override
  Future<CalibrationJob> fetchJob(String jobId,
      {CancelToken? cancelToken}) async {
    polls++;
    return job;
  }

  @override
  Future<Uint8List> fetchModel(String url, {CancelToken? cancelToken}) async {
    downloads++;
    if (failDownload) throw const CalibrationUploadException('내려받기 실패');
    // The native channel is mocked; no real mesh or filesystem access.
    return Uint8List.fromList([0x67, 0x6c, 0x54, 0x46]);
  }

  @override
  Future<CalibrationUploadReceipt> upload(
    String sessionPath, {
    required CancelToken cancelToken,
    void Function(CalibrationUploadProgress)? onProgress,
  }) {
    calls++;
    path = sessionPath;
    return result.future;
  }
}

void main() {
  BodyAnalysisResult? delivered;
  Future<void> show(WidgetTester tester, _Uploader service,
      {String? path = '/capture/session'}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(service.close);
    delivered = null;
    final router = GoRouter(initialLocation: '/analyzing', routes: [
      GoRoute(
          path: '/analyzing',
          builder: (_, __) => OnboardingAnalyzingScreen(sessionPath: path)),
      GoRoute(
          path: '/onboarding/result',
          builder: (_, state) {
            delivered = state.extra as BodyAnalysisResult?;
            return const Scaffold(body: Text('result destination'));
          }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      calibrationUploadServiceProvider.overrideWithValue(service),
    ], child: MaterialApp.router(routerConfig: router)));
  }

  testWidgets('uploads right away without a button', (tester) async {
    final service = _Uploader();
    await show(tester, service);
    await tester.pump();
    expect(service.calls, 1);
    expect(service.path, '/capture/session');
    expect(find.text('40초 정도 걸려.\n조금만 기다려줘!'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    service.result.complete(const CalibrationUploadReceipt('session', 'job-1'));
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
  });

  testWidgets('goes to the result after the animation once upload is accepted',
      (tester) async {
    final service = _Uploader();
    await show(tester, service);
    await tester.pump(const Duration(seconds: 10));
    service.result.complete(const CalibrationUploadReceipt('session', 'job-1'));
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('result destination'), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('result destination'), findsOneWidget);
  });

  testWidgets('waits for an upload still running after 40s', (tester) async {
    final service = _Uploader();
    await show(tester, service);
    await tester.pump(const Duration(seconds: 45));
    await tester.pump();
    expect(find.text('result destination'), findsNothing);
    service.result.complete(const CalibrationUploadReceipt('session', 'job-1'));
    await tester.pumpAndSettle();
    expect(find.text('result destination'), findsOneWidget);
  });

  testWidgets('a failed upload still continues to the result', (tester) async {
    final service = _Uploader();
    await show(tester, service);
    service.result
        .completeError(const CalibrationUploadException('전송 실패 — 재시도'));
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(find.text('result destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfigured server skips the upload and continues',
      (tester) async {
    final service = _Uploader(configured: false);
    await show(tester, service);
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.text('result destination'), findsOneWidget);
  });

  testWidgets('missing session skips the upload and continues', (tester) async {
    final service = _Uploader();
    await show(tester, service, path: null);
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.text('result destination'), findsOneWidget);
  });

  testWidgets('three steps go keypoints → 3D body → bone lengths in order',
      (tester) async {
    final service = _Uploader();
    await show(tester, service);
    final labels = ['관절 키포인트 추출', '3D 체형 만들기', '뼈 길이 추출'];
    expect(find.text('자동 촬영 4장 수집'), findsNothing);
    for (var i = 0; i < 2; i++) {
      expect(tester.getTopLeft(find.text(labels[i])).dy,
          lessThan(tester.getTopLeft(find.text(labels[i + 1])).dy));
    }
    // 처음엔 첫 단계만 진행 중, 나머지는 대기.
    expect(find.text('진행 중'), findsOneWidget);
    expect(find.text('대기 중'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 30)); // 3/4 지점: 두 단계 완료
    expect(find.text('완료'), findsNWidgets(2));
    expect(find.text('진행 중'), findsOneWidget);
    service.result.complete(const CalibrationUploadReceipt('session', 'job-1'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  if (!kBodyMeshReveal) {
    testWidgets(
        'flag off preserves the old flow without polling or downloading',
        (tester) async {
      final service = _Uploader();
      await show(tester, service);
      service.result
          .complete(const CalibrationUploadReceipt('session', 'job-1'));
      await tester.pump(const Duration(seconds: 41));
      await tester.pumpAndSettle();
      expect(service.polls, 0);
      expect(service.downloads, 0);
      expect(delivered, isNull);
    });
  } else {
    testWidgets(
        'polls and prepares during analysis, then delivers the ready mesh',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('bpt/body_mesh');
      final prepared = Completer<String>();
      var preparations = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'prepare') {
          preparations++;
          return prepared.future;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final service = _Uploader()..job = const CalibrationJob('running', 50);
      await show(tester, service);
      service.result
          .complete(const CalibrationUploadReceipt('session', 'job-1'));
      await tester.pump();
      expect(service.polls, 1);
      service.job = const CalibrationJob('done', 100, result: {
        'userHeightCm': 170,
        'modelGlbUrl': 'https://photos.example.test/synthetic.glb',
      });
      await tester.pump(const Duration(seconds: 35));
      expect(service.downloads, 1);
      expect(preparations, 1);
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('result destination'), findsNothing);
      expect(find.text('3D 몸 만드는 중'), findsNothing);
      prepared.complete('prepared-box');
      await tester.pumpAndSettle();
      expect(delivered?.meshId, 'prepared-box');
      expect(delivered?.summary['키'], '170.0 cm');
    });

    testWidgets('download failure keeps measurements and still continues',
        (tester) async {
      final service = _Uploader()
        ..failDownload = true
        ..job = const CalibrationJob('done', 100, result: {
          'userHeightCm': 170,
          'modelGlbUrl': 'https://photos.example.test/synthetic.glb',
        });
      await show(tester, service);
      service.result
          .complete(const CalibrationUploadReceipt('session', 'job-1'));
      await tester.pump(const Duration(seconds: 41));
      await tester.pumpAndSettle();
      expect(delivered?.meshId, isNull);
      expect(delivered?.summary['키'], '170.0 cm');
      expect(find.text('result destination'), findsOneWidget);
    });

    testWidgets('a job timeout continues with a placeholder result',
        (tester) async {
      final service = _Uploader()..job = const CalibrationJob('running', 50);
      await show(tester, service);
      service.result
          .complete(const CalibrationUploadReceipt('session', 'job-1'));
      await tester.pump();
      await tester.pump(const Duration(minutes: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('result destination'), findsOneWidget);
      expect(delivered?.meshId, isNull);
    });
  }
}
