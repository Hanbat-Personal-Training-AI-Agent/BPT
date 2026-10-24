import 'dart:async';

import 'package:bpt/features/onboarding/services/calibration_upload_service.dart';
import 'package:bpt/features/workout/data/deep_analysis_queue.dart';
import 'package:bpt/features/workout/data/deep_analysis_service.dart';
import 'package:bpt/features/workout/screens/deep_analysis_report_screen.dart';
import 'package:bpt/features/workout/screens/native_pose_workout_screen.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeDeepService extends DeepAnalysisService {
  FakeDeepService()
      : super(
            config: const CalibrationUploadConfig(
                apiBaseUrl: 'https://api.example/v1',
                storageHosts: ['storage.example']),
            tokenProvider: () async => null,
            userId: 'fake-user');

  int uploads = 0;
  int retries = 0;
  bool allowed = true;
  bool offline = false;
  DeepAnalysisJob job = const DeepAnalysisJob('running', 20);
  List<Map<String, dynamic>> saved = [];

  @override
  Future<List<Map<String, dynamic>>> loadQueue() async => saved;
  @override
  Future<void> saveQueue(List<Map<String, dynamic>> rows) async {
    saved = rows;
  }

  @override
  Future<bool> canUpload(DeepAnalysisCapture capture) async => allowed;
  @override
  Future<String> upload(DeepAnalysisCapture capture, CancelToken cancel,
      {void Function(String)? onProgress}) async {
    uploads++;
    if (offline) throw StateError('offline');
    return 'job-fake';
  }

  @override
  Future<DeepAnalysisJob> fetchJob(String jobId, CancelToken cancel) async =>
      job;
  @override
  Future<String> retryJob(String jobId, CancelToken cancel) async {
    retries++;
    return 'job-retry';
  }
}

Map<String, dynamic> setEvent() => {
      'setIndex': 1,
      'videoLocalPath': 'unused-synthetic-path.mp4',
      'deepAnalysis': {
        'schemaVersion': 1,
        'sessionId': 'set-fake',
        'timebase': 'video_ms',
        'reps': [
          {
            'repIndex': 1,
            'startMs': 0,
            'endMs': 1000,
            'side': 'left',
            'onDeviceWarnings': []
          }
        ]
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('리포트 타임라인을 누르면 정확한 영상 시각으로 이동한다', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DeepAnalysisReport(
      video: const SizedBox(height: 180, child: Text('합성 플레이어')),
      onSeek: seeks.add,
      report: const {
        'summary': {'title': '총평'},
        'reps': [],
        'timeline': [
          {
            't': 0,
            'title': '총평',
            'body': '같이 살펴보자!',
            'severity': 'info',
            'rep': null
          },
          {
            't': 12.25,
            'title': '3회 · 깊이 확인',
            'body': '같은 깊이로 가 보자.',
            'severity': 'warning',
            'rep': 3
          },
        ]
      },
    ))));
    expect(find.text('0:12'), findsOneWidget);
    await tester.tap(find.text('3회 · 깊이 확인'));
    expect(seeks, [const Duration(milliseconds: 12250)]);
    await tester.tap(find.text('총평'));
    expect(seeks.last, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('네이티브 세트 종료 이벤트가 버튼 없이 분석을 시작하고 화면을 닫아도 계속된다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = FakeDeepService();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      deepAnalysisServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    addTearDown(service.close);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        SystemChannels.platform, (_) async => null);
    messenger.setMockMethodCallHandler(
        SystemChannels.platform_views, (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('bpt/kori_voice'), (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('bpt/kori_voice'), null);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: NativePoseWorkoutScreen(
                exerciseId: 'squat', targetReps: 1, targetSets: 2))));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    // 준비 화면의 8px 넘침은 심층분석 위젯이 그려지기 전부터 난다(테스트 글꼴 Ahem). 여기서는 무시한다.
    tester.takeException();
    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    view.onPlatformViewCreated!(71);
    final message = const StandardMethodCodec()
        .encodeMethodCall(MethodCall('onSetEnd', setEvent()));
    final completed = Completer<void>();
    messenger.handlePlatformMessage('${NativePoseWorkoutScreen.viewType}/71',
        message, (_) => completed.complete());
    await tester.pump();
    await completed.future;
    await tester.pump();
    expect(service.uploads, 1);
    expect(find.text('심층분석 받기'), findsNothing);
    expect(container.read(deepAnalysisQueueProvider)['set-fake']?['status'],
        'running');
    final recordId = container
        .read(deepAnalysisQueueProvider)['set-fake']!['recordId'] as String;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(body: DeepAnalysisStatus(recordId: recordId)))));
    expect(find.text('심층분석 중…'), findsOneWidget);
    service.job = const DeepAnalysisJob('done', 100);
    await container.read(deepAnalysisQueueProvider.notifier).tick();
    await tester.pump();
    expect(find.text('완료'), findsOneWidget);
    expect(service.uploads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(minutes: 10)); // 화면이 남긴 지연 타이머를 소진한다
    debugDefaultTargetPlatformOverride = null; // tearDown은 불변식 검사보다 늦다
  });

  testWidgets('Wi-Fi 대기·중복 이벤트·복원·서버 실패 재시도', (tester) async {
    final service = FakeDeepService()..allowed = false;
    var queue = DeepAnalysisQueue(service);
    await queue.ready;
    await queue.enqueueSet(setEvent(), 'squat', recordId: 'record-1');
    expect(service.uploads, 0);
    service.allowed = true;
    await queue.tick();
    await queue.enqueueSet(setEvent(), 'squat', recordId: 'record-1');
    expect(service.uploads, 1);
    expect(service.saved.single['manifest'], isNull);
    queue.dispose();
    service.job = const DeepAnalysisJob('failed', 20, retryable: true);
    queue = DeepAnalysisQueue(service);
    await queue.ready;
    await tester.pump();
    expect(service.uploads, 1);
    expect(service.retries, 1);
    expect(service.saved.single['jobId'], 'job-retry');
    service.job = const DeepAnalysisJob('failed', 20);
    await queue.tick();
    expect(service.saved.single['status'], 'failed');
    queue.dispose();
    service.close();
  });

  testWidgets('연결 실패는 조용히 지연 후 같은 세션으로 재시도한다', (tester) async {
    final service = FakeDeepService()..offline = true;
    final queue = DeepAnalysisQueue(service);
    await queue.ready;
    await queue.enqueueSet(setEvent(), 'squat', recordId: 'record-1');
    expect(service.saved.single['status'], 'waiting');
    expect(service.saved.single['failures'], 1);
    await queue.tick();
    expect(service.uploads, 1);
    queue.dispose();
    final restored = Map<String, dynamic>.from(service.saved.single)
      ..['nextAttemptMs'] = 0;
    service.saved = [restored];
    service.offline = false;
    final resumed = DeepAnalysisQueue(service);
    await resumed.ready;
    await tester.pump();
    expect(service.uploads, 2);
    expect(service.saved.single['status'], 'running');
    resumed.dispose();
    service.close();
  });
}
