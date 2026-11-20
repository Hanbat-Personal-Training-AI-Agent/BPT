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
  FakeDeepService({super.userId = 'fake-user'})
      : super(
            config: const CalibrationUploadConfig(
                apiBaseUrl: 'https://api.example/v1',
                storageHosts: ['storage.example']),
            tokenProvider: () async => null);

  int uploads = 0;
  int retries = 0;
  bool allowed = true;
  bool offline = false;
  int fetches = 0;
  Object? fetchError;
  Completer<DeepAnalysisJob>? pendingJob;
  CancelToken? lastCancel;
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
      _fetch(cancel);
  Future<DeepAnalysisJob> _fetch(CancelToken cancel) async {
    fetches++;
    lastCancel = cancel;
    if (fetchError != null) throw fetchError!;
    return pendingJob?.future ?? Future.value(job);
  }

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

  testWidgets('로그아웃 상태에서는 세트 이벤트를 접수하지 않는다', (tester) async {
    final service = FakeDeepService(userId: null);
    final queue = DeepAnalysisQueue(service);
    await queue.ready;
    await queue.enqueueSet(setEvent(), 'squat', recordId: 'record-1');
    expect(service.saved, isEmpty);
    expect(service.uploads, 0);
    queue.dispose();
    service.close();
  });

  testWidgets('계정 변경은 열린 리포트 요청을 취소하고 다른 계정으로 재조회하지 않는다', (tester) async {
    final first = FakeDeepService()..pendingJob = Completer<DeepAnalysisJob>();
    final second = FakeDeepService();
    final selected = StateProvider<DeepAnalysisService>((ref) => first);
    final container = ProviderContainer(overrides: [
      deepAnalysisServiceProvider.overrideWith((ref) => ref.watch(selected)),
    ]);
    addTearDown(container.dispose);
    addTearDown(first.close);
    addTearDown(second.close);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child:
          const MaterialApp(home: DeepAnalysisReportScreen(jobId: 'old-job')),
    ));
    await tester.pump();
    expect(first.fetches, 1);
    container.read(selected.notifier).state = second;
    await tester.pump();
    expect(first.lastCancel!.isCancelled, isTrue);
    expect(find.text('계정이 바뀌었어. 기록에서 다시 열어 줘.'), findsOneWidget);
    first.pendingJob!.complete(const DeepAnalysisJob('running', 20));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 51));
    expect(second.fetches, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('영구 HTTP 실패는 멈추고 인증·서버 오류는 재시도한다', (tester) async {
    for (final status in [400, 404, 409, 413, 422, 401, 403, 429, 503]) {
      final options = RequestOptions(path: '/deep-analysis/jobs/job-fake');
      final service = FakeDeepService()
        ..fetchError = DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: status),
          type: DioExceptionType.badResponse,
        );
      final queue = DeepAnalysisQueue(service);
      await queue.ready;
      await queue.enqueueSet(setEvent(), 'squat', recordId: 'record-1');
      expect(
          service.saved.single['status'],
          status == 401 || status == 403 || status == 429 || status == 503
              ? 'waiting'
              : 'failed',
          reason: 'HTTP $status');
      await queue.tick();
      expect(service.fetches, 1);
      queue.dispose();
      service.close();
    }
  });

  test('녹화 OFF와 잘못된 세션은 대기열에 넣지 않는다', () {
    expect(DeepAnalysisCapture.fromSet({}, 'squat'), isNull);
    final event = setEvent();
    (event['deepAnalysis'] as Map).remove('sessionId');
    expect(DeepAnalysisCapture.fromSet(event, 'squat'), isNull);
  });

  testWidgets('낮은 검출 근거와 임시 기준은 확정 판정처럼 표시하지 않는다', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DeepAnalysisReport(
      video: const SizedBox(height: 80),
      onSeek: (_) {},
      report: {
        'rules': const {'placeholder': true},
        'timeline': const [],
        'reps': [
          {
            'repIndex': 1,
            'confidence': .1,
            'validity': const {
              'confidenceSource': 'missing',
              'detectionSupport': 'insufficient'
            },
            'anglesDeg': {
              for (final key in ['knee', 'hip', 'elbow', 'shoulder', 'torso'])
                key: {'top': 170, 'bottom': 90}
            },
            'tempoSeconds': const {},
            'handPath': const {},
            'trunkStability': const {},
            'symmetryDeg': const {
              'knee': {'max': 0}
            },
            'primaryJoint': 'knee',
            'fatigueDrift': const {'comparable': false},
            'catalogMeasurements': const [
              {'assessment': 'withheld'}
            ],
          }
        ],
      },
    ))));
    expect(find.textContaining('코칭 기준은 아직 검증 중'), findsOneWidget);
    expect(find.text('1회 · 추정값 · 판정 보류'), findsOneWidget);
    await tester.tap(find.text('1회 · 추정값 · 판정 보류'));
    await tester.pumpAndSettle();
    expect(find.textContaining('아래 수치는 추정값'), findsOneWidget);
    expect(find.text('일부 자세 항목은 판정에 필요한 조건을 확인하지 못했어.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // A missing wrist must not withhold unrelated knee/ROM measurements.
    final report = tester
        .widget<DeepAnalysisReport>(find.byType(DeepAnalysisReport))
        .report;
    final rep = (report['reps'] as List).single as Map;
    rep['confidence'] = .9;
    rep['validity'] = {
      'confidenceSource': '2d_detection_support',
      'detectionSupport': 'available'
    };
    rep['metricValidity'] = {
      'handPath': {
        'assessment': 'withheld',
        'reasons': ['low_joint_support']
      }
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DeepAnalysisReport(
      report: report,
      video: const SizedBox(height: 80),
      onSeek: (_) {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('1회 · 자세히 보기'), findsOneWidget);
    expect(tester.widget<Text>(find.textContaining('손목 경로')).data,
        contains('판정 보류'));
    expect(tester.widget<Text>(find.textContaining('ROM 확인 불가')).data,
        isNot(contains('판정 보류')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('기준 반복 수만 부족하면 관절·추적 부족 경고를 띄우지 않는다', (tester) async {
    final rep = <String, dynamic>{
      'repIndex': 1,
      'confidence': .9,
      'anglesDeg': {
        for (final key in ['knee', 'hip', 'elbow', 'shoulder', 'torso'])
          key: {'top': 170, 'bottom': 90}
      },
      'tempoSeconds': {},
      'handPath': {},
      'trunkStability': {},
      'symmetryDeg': {
        'knee': {'max': 0}
      },
      'primaryJoint': 'knee',
      'fatigueDrift': {'comparable': false},
      'metricValidity': {
        for (final key in ['depthDriftDeg', 'romDropDeg', 'tempoDriftRatio'])
          key: {
            'assessment': 'withheld',
            'reasons': ['requires_baseline_reps']
          },
      },
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DeepAnalysisReport(
      report: {
        'timeline': const [],
        'reps': [rep]
      },
      video: const SizedBox(height: 80),
      onSeek: (_) {},
    ))));
    await tester.tap(find.text('1회 · 자세히 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('일부 관절이나 추적 근거가 부족'), findsNothing);
    expect(find.textContaining('처음 반복의 영상 근거가 부족'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('기록 상세는 그 운동 UUID의 세트만 연결한다', (tester) async {
    final service = FakeDeepService()
      ..saved = [
        {
          'sessionId': 'set-a1',
          'recordId': 'record-a',
          'setNumber': 1,
          'status': 'done',
          'jobId': 'job-a1'
        },
        {
          'sessionId': 'set-a2',
          'recordId': 'record-a',
          'setNumber': 2,
          'status': 'done',
          'jobId': 'job-a2'
        },
        {
          'sessionId': 'set-b9',
          'recordId': 'record-b',
          'setNumber': 9,
          'status': 'done',
          'jobId': 'job-b9'
        },
      ];
    final container = ProviderContainer(overrides: [
      deepAnalysisServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    addTearDown(service.close);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: Scaffold(body: DeepAnalysisSection(recordId: 'record-a')))));
    await tester.pump();
    expect(find.text('1세트 심층분석 · 완료'), findsOneWidget);
    expect(find.text('2세트 심층분석 · 완료'), findsOneWidget);
    expect(find.textContaining('9세트'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

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
