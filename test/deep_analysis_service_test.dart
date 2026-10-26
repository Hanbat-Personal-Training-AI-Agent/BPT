import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/features/onboarding/services/calibration_upload_service.dart';
import 'package:bpt/features/workout/data/deep_analysis_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const config = CalibrationUploadConfig(
    apiBaseUrl: 'https://api.example/v1', storageHosts: ['storage.example']);

class Adapter implements HttpClientAdapter {
  Adapter(this.handle);
  final Future<ResponseBody> Function(RequestOptions, List<int>) handle;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    return handle(options, bytes);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(Object data) =>
    ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('동시 401은 기존 인증 갱신 한 번을 공유하고 재요청한다', () async {
    var refreshes = 0;
    final refreshDio = Dio(BaseOptions(baseUrl: 'https://spring.example'))
      ..httpClientAdapter = Adapter((request, bytes) async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return json({'accessToken': 'fresh', 'refreshToken': 'fresh-refresh'});
      });
    final auth =
        ApiClient(baseUrl: 'https://spring.example', refreshDio: refreshDio)
          ..setAuthToken('expired')
          ..setRefreshToken('refresh');
    var requests = 0;
    final api = Dio()
      ..httpClientAdapter = Adapter((request, bytes) async {
        requests++;
        return request.headers['Authorization'] == 'Bearer fresh'
            ? json({'status': 'running'})
            : ResponseBody.fromString('{}', 401);
      });
    final service = DeepAnalysisService(
        config: config,
        tokenProvider: () async => auth.authToken,
        refreshToken: auth.refreshAccessToken,
        userId: 'a',
        api: api);
    addTearDown(service.close);
    final results = await Future.wait([
      service.fetchJob('job-a', CancelToken()),
      service.fetchJob('job-b', CancelToken()),
    ]);
    expect(results.map((job) => job.status), ['running', 'running']);
    expect(refreshes, 1);
    expect(requests, 4);
  });

  test('갱신 뒤에도 401이면 같은 요청을 다시 갱신하지 않는다', () async {
    var requests = 0;
    var refreshes = 0;
    final api = Dio()
      ..httpClientAdapter = Adapter((request, bytes) async {
        requests++;
        return ResponseBody.fromString('{}', 401);
      });
    final service = DeepAnalysisService(
        config: config,
        tokenProvider: () async => 'expired',
        refreshToken: (_) async {
          refreshes++;
          return 'fresh';
        },
        api: api);
    addTearDown(service.close);
    await expectLater(
        service.fetchJob('job-a', CancelToken()), throwsA(isA<DioException>()));
    expect(requests, 2);
    expect(refreshes, 1);
  });

  test('인증 갱신 도중 로그아웃하면 원 요청을 재개하지 않는다', () async {
    final refreshing = Completer<void>();
    final released = Completer<String?>();
    var requests = 0;
    final api = Dio()
      ..httpClientAdapter = Adapter((request, bytes) async {
        requests++;
        return ResponseBody.fromString('{}', 401);
      });
    final service = DeepAnalysisService(
        config: config,
        tokenProvider: () async => 'expired',
        api: api,
        refreshToken: (_) {
          refreshing.complete();
          return released.future;
        });
    final request = service.fetchJob('job-a', CancelToken());
    final check = expectLater(request, throwsA(isA<DioException>()));
    await refreshing.future;
    service.close();
    released.complete('new-account-token');
    await check;
    expect(requests, 1);
  });

  test('계정과 API 주소별 영속 이력은 서로 읽지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    DeepAnalysisService service(String? user, CalibrationUploadConfig cfg) =>
        DeepAnalysisService(
            config: cfg, tokenProvider: () async => 'token', userId: user);
    final a = service('a', config);
    final b = service('b', config);
    final otherApi = service(
        'a',
        const CalibrationUploadConfig(
            apiBaseUrl: 'https://other.example/v1',
            storageHosts: ['storage.example']));
    final anonymous = service(null, config);
    addTearDown(() {
      a.close();
      b.close();
      otherApi.close();
      anonymous.close();
    });
    await a.saveQueue([
      {'sessionId': 'set-a', 'jobId': 'job-a', 'status': 'done'}
    ]);
    expect((await a.loadQueue()).single['jobId'], 'job-a');
    expect(await b.loadQueue(), isEmpty);
    expect(await otherApi.loadQueue(), isEmpty);
    await anonymous.saveQueue([
      {'sessionId': 'anonymous'}
    ]);
    expect(await anonymous.loadQueue(), isEmpty);
  });

  test('업로드 API만 인증하고 서명 PUT에는 토큰을 보내지 않는다', () async {
    final dir = await Directory.systemTemp.createTemp('bpt-synthetic-test-');
    addTearDown(() => dir.delete(recursive: true));
    final video =
        await File('${dir.path}/synthetic.mp4').writeAsBytes([0, 1, 2]);
    var puts = 0;
    final api = Dio()
      ..httpClientAdapter = Adapter((request, bytes) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.headers['Idempotency-Key'], 'set-test');
        if (request.path.endsWith('/complete')) {
          return json({'status': 'accepted', 'jobId': 'job-test'});
        }
        return json({
          'status': 'upload_required',
          'uploadId': 'upload-test',
          'files': [
            for (final name in ['video.mp4', 'reps.json'])
              {
                'name': name,
                'method': 'PUT',
                'url': 'https://storage.example/$name?signature=test'
              }
          ]
        });
      });
    final storage = Dio()
      ..httpClientAdapter = Adapter((request, bytes) async {
        puts++;
        expect(request.headers.keys.map((key) => key.toLowerCase()),
            isNot(contains('authorization')));
        expect(request.followRedirects, isFalse);
        expect(bytes, isNotEmpty);
        return ResponseBody.fromString('', 200);
      });
    final service = DeepAnalysisService(
        config: config,
        tokenProvider: () async => 'test-token',
        userId: 'a',
        api: api,
        storage: storage);
    addTearDown(service.close);
    expect(
        await service.upload(
            DeepAnalysisCapture(video.path,
                {'sessionId': 'set-test', 'exerciseId': 'squat', 'reps': []}),
            CancelToken()),
        'job-test');
    expect(puts, 2);
  });

  test('다운로드마다 URL 갱신·무인증 GET·별도 임시 디렉터리', () async {
    var fetches = 0;
    final api = Dio()
      ..httpClientAdapter = Adapter((request, bytes) async {
        fetches++;
        return json({
          'status': 'done',
          'result': {
            'report': {
              'schemaVersion': 1,
              'reps': [],
              'timeline': [],
              'summary': {}
            },
            'videoUrl': 'https://storage.example/video.mp4?signature=$fetches',
          }
        });
      });
    final storage = Dio()
      ..httpClientAdapter = Adapter((request, bytes) async {
        expect(request.uri.queryParameters['signature'], '$fetches');
        expect(request.headers.keys.map((key) => key.toLowerCase()),
            isNot(contains('authorization')));
        return ResponseBody.fromBytes([0, 1, 2], 200);
      });
    final service = DeepAnalysisService(
        config: config,
        tokenProvider: () async => 'test-token',
        userId: 'a',
        api: api,
        storage: storage);
    addTearDown(service.close);
    final first = await service.downloadVideo('job-test', CancelToken());
    addTearDown(() => first.parent.delete(recursive: true));
    final second = await service.downloadVideo('job-test', CancelToken());
    addTearDown(() => second.parent.delete(recursive: true));
    expect(fetches, 2);
    expect(first.path, isNot(second.path));
    expect(await first.readAsBytes(), [0, 1, 2]);
  });

  test('닫힌 서비스는 지연된 토큰 결과로 요청하지 않는다', () async {
    final token = Completer<String?>();
    var requests = 0;
    final api = Dio()
      ..httpClientAdapter = Adapter((request, bytes) async {
        requests++;
        return json({'status': 'running'});
      });
    final service = DeepAnalysisService(
        config: config,
        tokenProvider: () => token.future,
        userId: 'a',
        api: api);
    final result = service.fetchJob('job-test', CancelToken());
    service.close();
    token.complete('new-account-token');
    await expectLater(result, throwsA(isA<CalibrationUploadException>()));
    expect(requests, 0);
  });
}
