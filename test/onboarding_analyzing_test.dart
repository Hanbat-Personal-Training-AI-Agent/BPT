import 'dart:async';
import 'package:bpt/features/onboarding/services/calibration_result_store.dart';

import 'package:bpt/features/onboarding/models/body_analysis_result.dart';
import 'package:bpt/features/onboarding/models/calibration_capture.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/session_fixture.dart';
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
  Completer<CalibrationJob>? pendingPoll;
  Completer<Uint8List>? pendingDownload;

  @override
  Future<CalibrationJob> fetchJob(String jobId,
      {CancelToken? cancelToken}) async {
    polls++;
    if (pendingPoll != null) return pendingPoll!.future;
    return job;
  }

  @override
  Future<Uint8List> fetchModel(String url, {CancelToken? cancelToken}) async {
    downloads++;
    if (pendingDownload != null) return pendingDownload!.future;
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
  late AuthNotifier auth;
  Future<void> show(WidgetTester tester, _Uploader service,
      {String? path = '/capture/session',
      bool signedIn = true,
      bool ownedCapture = true,
      bool staleCapture = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(service.close);
    delivered = null;
    SharedPreferences.setMockInitialValues({});
    auth = (await sessionFixture(await SharedPreferences.getInstance())).auth;
    if (!signedIn) await auth.logout();
    final capture = ownedCapture
        ? CalibrationCapture(sessionPath: path, session: auth.captureSession())
        : null;
    if (staleCapture) {
      await auth.logout();
      await auth.login('B', 'password');
    }
    final router = GoRouter(initialLocation: '/analyzing', routes: [
      GoRoute(
          path: '/analyzing',
          builder: (_, __) =>
              OnboardingAnalyzingScreen(sessionPath: path, capture: capture)),
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
      authNotifierProvider.overrideWith((ref) => auth),
    ], child: MaterialApp.router(routerConfig: router)));
  }

  testWidgets(
      'disposing an accepted running-job screen stops local observation',
      (tester) async {
    final service = _Uploader()..job = const CalibrationJob('running', 50);
    await show(tester, service);
    service.result
        .complete(const CalibrationUploadReceipt('session', 'accepted-job'));
    await tester.pump();
    expect(service.polls,
        (kBodyMeshReveal || CalibrationResultStore.enabled) ? 1 : 0);
    final before = service.polls;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // No pump-away timer: widget-test teardown itself checks no pending timers.
    expect(service.polls, before);
    expect(
        service.calls, 1); // Accepted upload is not submitted or deleted again.
  });

  testWidgets(
      'setup-only accepted job continues across result navigation under its account owner',
      (tester) async {
    final service = _Uploader()..job = const CalibrationJob('running', 50);
    await show(tester, service);
    service.result
        .complete(const CalibrationUploadReceipt('session', 'accepted-job'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(find.text('result destination'), findsOneWidget);
    service.job = const CalibrationJob('done', 100, result: {
      'boneLengthData': {
        'unit': 'cm',
        'segments': {'hip_width': 28.0}
      },
    });
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(CalibrationResultStore.accountResultKey('A')),
        contains('accepted-job'));
  }, skip: !CalibrationResultStore.enabled || kBodyMeshReveal);

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

  testWidgets(
      'legacy path is not silently assigned to the account present at mount',
      (tester) async {
    final service = _Uploader();
    await show(tester, service, ownedCapture: false);
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(service.polls, 0);
    expect(delivered?.summary ?? {}, isEmpty);
  });

  testWidgets(
      'capture A lease invalidated before mount cannot be uploaded by B',
      (tester) async {
    final service = _Uploader();
    await show(tester, service, staleCapture: true);
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(service.polls, 0);
    expect(service.downloads, 0);
    expect(delivered, isNull);
    expect(find.text('result destination'), findsNothing);
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

  testWidgets(
      'anonymous local onboarding can continue without uploading or using a result',
      (tester) async {
    final service = _Uploader();
    await show(tester, service, signedIn: false);
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(service.polls, 0);
    expect(service.downloads, 0);
    expect(delivered?.summary ?? {}, isEmpty);
    expect(find.text('result destination'), findsOneWidget);
  });

  testWidgets(
      'late accepted upload after account switch does not poll or navigate',
      (tester) async {
    final service = _Uploader();
    await show(tester, service);
    await auth.logout();
    await auth.login('B', 'password');
    service.result
        .complete(const CalibrationUploadReceipt('session', 'old-A-job'));
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(service.polls, 0);
    expect(service.downloads, 0);
    expect(find.text('result destination'), findsNothing);
    expect(delivered, isNull);
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
        'mesh off never downloads and only enabled setup observes the accepted job',
        (tester) async {
      final service = _Uploader();
      await show(tester, service);
      service.result
          .complete(const CalibrationUploadReceipt('session', 'job-1'));
      await tester.pump(const Duration(seconds: 41));
      await tester.pumpAndSettle();
      expect(service.polls, CalibrationResultStore.enabled ? 1 : 0);
      expect(service.downloads, 0);
      expect(delivered, isNull);
    });
  } else {
    testWidgets('late job and model responses cannot reach a different account',
        (tester) async {
      final service = _Uploader()..pendingPoll = Completer<CalibrationJob>();
      await show(tester, service);
      service.result
          .complete(const CalibrationUploadReceipt('session', 'job-A'));
      await tester.pump();
      expect(service.polls, 1);
      await auth.logout();
      await auth.login('B', 'password');
      service.pendingPoll!.complete(const CalibrationJob('done', 100, result: {
        'userHeightCm': 170,
        'modelGlbUrl': 'https://photos.example.test/old.glb',
      }));
      await tester.pump(const Duration(seconds: 41));
      await tester.pumpAndSettle();
      expect(service.downloads, 0);
      expect(delivered, isNull);
      expect(find.text('result destination'), findsNothing);
    });

    testWidgets('late model download cannot prepare or display an old mesh',
        (tester) async {
      final service = _Uploader()
        ..pendingDownload = Completer<Uint8List>()
        ..job = const CalibrationJob('done', 100, result: {
          'userHeightCm': 170,
          'modelGlbUrl': 'https://photos.example.test/old.glb',
        });
      await show(tester, service);
      service.result
          .complete(const CalibrationUploadReceipt('session', 'job-A'));
      await tester.pump();
      expect(service.downloads, 1);
      await auth.logout();
      await auth.login('B', 'password');
      service.pendingDownload!.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pump(const Duration(seconds: 41));
      await tester.pumpAndSettle();
      expect(delivered, isNull);
      expect(find.text('result destination'), findsNothing);
    });

    testWidgets('late native preparation is released after A to B to A login',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('bpt/body_mesh');
      final prepared = Completer<String>();
      final released = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'prepare') return prepared.future;
        if (call.method == 'release') {
          released.add((call.arguments as Map)['meshId'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final service = _Uploader()
        ..job = const CalibrationJob('done', 100, result: {
          'userHeightCm': 170,
          'modelGlbUrl': 'https://photos.example.test/old.glb',
        });
      await show(tester, service);
      service.result
          .complete(const CalibrationUploadReceipt('session', 'job-A'));
      await tester.pump();
      await auth.logout();
      await auth.login('B', 'password');
      await auth.logout();
      await auth.login('A', 'password');
      prepared.complete('old-A-mesh');
      await tester.pump(const Duration(seconds: 41));
      await tester.pumpAndSettle();
      expect(released, contains('old-A-mesh'));
      expect(delivered, isNull);
      expect(find.text('result destination'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

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
      await tester.pump(const Duration(seconds: 32));
      service.job = const CalibrationJob('done', 100, result: {
        'userHeightCm': 170,
        'modelGlbUrl': 'https://photos.example.test/synthetic.glb',
        'smplBeta': [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        'boneLengthData': {
          'unit': 'cm',
          'segments': {'hip_width': 28.0}
        },
      });
      await tester.pump(const Duration(seconds: 3));
      expect(service.downloads, 1);
      expect(preparations, 1);
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('result destination'), findsNothing);
      expect(find.text('3D 몸 만드는 중'), findsNothing);
      prepared.complete('prepared-box');
      await tester.pumpAndSettle();
      expect(delivered?.meshId, 'prepared-box');
      expect(delivered?.session?.userId, 'A');
      expect(delivered?.session?.isCurrent, isTrue);
      expect(delivered?.summary['키'], '170.0 cm');
      if (CalibrationResultStore.enabled) {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(CalibrationResultStore.accountResultKey('A')),
            contains('job-1'));
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('download failure keeps measurements and still continues',
        (tester) async {
      final service = _Uploader()
        ..failDownload = true
        ..job = const CalibrationJob('done', 100, result: {
          'userHeightCm': 170,
          'modelGlbUrl': 'https://photos.example.test/synthetic.glb',
          'boneLengthData': {
            'unit': 'cm',
            'segments': {'hip_width': 28.0}
          },
        });
      await show(tester, service);
      service.result
          .complete(const CalibrationUploadReceipt('session', 'job-1'));
      await tester.pump(const Duration(seconds: 41));
      await tester.pumpAndSettle();
      expect(delivered?.meshId, isNull);
      expect(delivered?.summary['키'], '170.0 cm');
      if (CalibrationResultStore.enabled) {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(CalibrationResultStore.accountResultKey('A')),
            contains('job-1'));
      }
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
