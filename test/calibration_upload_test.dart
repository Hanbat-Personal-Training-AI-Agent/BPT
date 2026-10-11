import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bpt/features/onboarding/services/calibration_upload_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = CalibrationUploadConfig(
  apiBaseUrl: 'https://calibration.example.test/v1',
  storageHosts: ['photos.example.test'],
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
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

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    );

Map<String, dynamic> _prepared({String host = 'photos.example.test'}) => {
      'status': 'upload_required',
      'uploadId': 'upload-1',
      'files': [
        for (final name in [
          'manifest.json',
          ...CalibrationBundle.viewNames.map((view) => 'view_$view.jpg')
        ])
          {
            'name': name,
            'method': 'PUT',
            'url': 'https://$host/$name?signature=secret'
          }
      ],
    };

void main() {
  late Directory directory;
  late Map<String, dynamic> manifest;
  late Dio api;
  late Dio storage;
  late List<RequestOptions> apiCalls;
  late List<RequestOptions> storageCalls;
  late Map<String, List<int>> uploaded;

  Future<void> writeManifest() => File('${directory.path}/manifest.json')
      .writeAsString(jsonEncode(manifest));

  CalibrationUploadService service(
          {CalibrationUploadConfig config = _config,
          String? token = 'user-token'}) =>
      CalibrationUploadService(
          config: config,
          tokenProvider: () async => token,
          api: api,
          storage: storage);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bpt-upload-test-');
    manifest = {
      'schemaVersion': 1,
      'sessionId': 'test-session-1',
      'keypointFormat': 'coco17_pixel_unmirrored',
      'userHeightCm': 175,
      'imageWidth': 1080,
      'imageHeight': 1920,
      'views': <Map<String, dynamic>>[
        for (final view in CalibrationBundle.viewNames)
          {
            'label': view,
            'file': 'view_$view.jpg',
            'keypoints':
                List.generate(17, (i) => [i.toDouble(), i.toDouble(), 0.9]),
          }
      ],
    };
    await writeManifest();
    for (var i = 0; i < CalibrationBundle.viewNames.length; i++) {
      // Synthetic bytes, not a real person's photo. Transport must preserve them.
      await File('${directory.path}/view_${CalibrationBundle.viewNames[i]}.jpg')
          .writeAsBytes([0xff, 0xd8, i, 0xff, 0xd9]);
    }
    await File('${directory.path}/debug.csv').writeAsString('DO NOT UPLOAD');
    apiCalls = [];
    storageCalls = [];
    uploaded = {};
    api = Dio()
      ..httpClientAdapter = _Adapter((options, _) async {
        apiCalls.add(options);
        return options.path.endsWith('/complete')
            ? _json({'status': 'accepted', 'jobId': 'job-1'}, 202)
            : _json(_prepared(), 201);
      });
    storage = Dio()
      ..httpClientAdapter = _Adapter((options, bytes) async {
        storageCalls.add(options);
        uploaded[options.uri.pathSegments.last] = bytes;
        return ResponseBody.fromString('', 200);
      });
  });
  tearDown(() async {
    api.close(force: true);
    storage.close(force: true);
    await directory.delete(recursive: true);
  });

  test('native bundle contains exactly four photos and manifest, no logs',
      () async {
    final bundle = await CalibrationBundle.load(directory.path);
    expect(bundle.sessionId, 'test-session-1');
    expect(bundle.files.length, 5);
    expect(bundle.files.any((file) => file.name == 'debug.csv'), isFalse);
  });

  test('rejects missing photo before any API request', () async {
    await File('${directory.path}/view_back.jpg').delete();
    await expectLater(
        service().upload(directory.path, cancelToken: CancelToken()),
        throwsA(isA<CalibrationUploadException>()));
    expect(apiCalls, isEmpty);
  });

  test(
      'rejects manifest path traversal, duplicate views and malformed keypoints',
      () async {
    final views = manifest['views'] as List;
    views[0]['file'] = '../private.jpg';
    await writeManifest();
    await expectLater(CalibrationBundle.load(directory.path),
        throwsA(isA<CalibrationUploadException>()));
    views[0]['file'] = 'view_front.jpg';
    views[1] = Map<String, dynamic>.from(views[0]);
    await writeManifest();
    await expectLater(CalibrationBundle.load(directory.path),
        throwsA(isA<CalibrationUploadException>()));
    views[1]['label'] = 'rightfront';
    views[1]['file'] = 'view_rightfront.jpg';
    views[0]['keypoints'] = [
      [1, 2, 3]
    ];
    await writeManifest();
    await expectLater(CalibrationBundle.load(directory.path),
        throwsA(isA<CalibrationUploadException>()));
  });

  test('rejects symlink photo', () async {
    final file = File('${directory.path}/view_back.jpg');
    await file.delete();
    await Link(file.path).create('${directory.path}/debug.csv');
    await expectLater(CalibrationBundle.load(directory.path),
        throwsA(isA<CalibrationUploadException>()));
  });

  test(
      'unconfigured, HTTP endpoint, missing hosts and missing auth fail closed',
      () async {
    for (final config in [
      const CalibrationUploadConfig(),
      const CalibrationUploadConfig(
          apiBaseUrl: 'http://unsafe.test',
          storageHosts: ['photos.example.test']),
      const CalibrationUploadConfig(apiBaseUrl: 'https://api.example.test')
    ]) {
      await expectLater(
          service(config: config)
              .upload(directory.path, cancelToken: CancelToken()),
          throwsA(isA<CalibrationUploadException>()));
    }
    await expectLater(
        service(token: null).upload(directory.path, cancelToken: CancelToken()),
        throwsA(isA<CalibrationUploadException>()));
    expect(apiCalls, isEmpty);
    expect(storageCalls, isEmpty);
  });

  test(
      'streams original bytes, separates auth, confirms then persists only receipt',
      () async {
    final progress = <CalibrationUploadProgress>[];
    final receipt = await service().upload(directory.path,
        cancelToken: CancelToken(), onProgress: progress.add);
    expect(receipt.jobId, 'job-1');
    expect(apiCalls.length, 2);
    expect(apiCalls.first.data['clientSessionId'], 'test-session-1');
    expect((apiCalls.first.data['files'] as List).length, 5);
    expect(apiCalls.last.path,
        'https://calibration.example.test/v1/calibrations/uploads/upload-1/complete');
    for (final call in apiCalls) {
      expect(call.headers['Authorization'], 'Bearer user-token');
      expect(call.headers['Idempotency-Key'], 'test-session-1');
      expect(call.followRedirects, isFalse);
    }
    expect(storageCalls.length, 5);
    for (final call in storageCalls) {
      expect(call.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')));
      expect(call.followRedirects, isFalse);
      final name = call.uri.pathSegments.last;
      expect(
          uploaded[name], await File('${directory.path}/$name').readAsBytes());
      expect(call.headers[HttpHeaders.contentLengthHeader],
          uploaded[name]!.length);
    }
    expect(progress.last.stage, CalibrationUploadStage.accepted);
    expect(progress.last.fraction, 1);
    final saved =
        await File('${directory.path}/upload_receipt.json').readAsString();
    expect(saved, contains('job-1'));
    expect(saved, isNot(contains('user-token')));
    expect(saved, isNot(contains('signature')));
    expect(await File('${directory.path}/view_front.jpg').exists(), isTrue);
  });

  test('failed signed PUT never completes; retry uses same session id',
      () async {
    var fail = true;
    storage.httpClientAdapter = _Adapter((options, bytes) async {
      storageCalls.add(options);
      return ResponseBody.fromString('', fail ? 403 : 200);
    });
    final uploader = service();
    await expectLater(
        uploader.upload(directory.path, cancelToken: CancelToken()),
        throwsA(isA<CalibrationUploadException>()));
    expect(apiCalls.length, 1);
    expect(
        await File('${directory.path}/upload_receipt.json').exists(), isFalse);
    expect(await File('${directory.path}/view_front.jpg').exists(), isTrue);
    fail = false;
    await uploader.upload(directory.path, cancelToken: CancelToken());
    expect(apiCalls.map((call) => call.headers['Idempotency-Key']).toSet(),
        {'test-session-1'});
    expect(apiCalls.length, 3);
  });

  test(
      'lost completion response is retried idempotently without uploading again if accepted',
      () async {
    var accepted = false;
    api.httpClientAdapter = _Adapter((options, _) async {
      apiCalls.add(options);
      if (options.path.endsWith('/complete')) {
        accepted = true;
        return _json({'error': 'lost response'}, 503);
      }
      return accepted
          ? _json({'status': 'accepted', 'jobId': 'job-1'})
          : _json(_prepared());
    });
    final uploader = service();
    await expectLater(
        uploader.upload(directory.path, cancelToken: CancelToken()),
        throwsA(isA<CalibrationUploadException>()));
    expect(storageCalls.length, 5);
    expect(
        await File('${directory.path}/upload_receipt.json').exists(), isFalse);
    final receipt =
        await uploader.upload(directory.path, cancelToken: CancelToken());
    expect(receipt.jobId, 'job-1');
    expect(storageCalls.length, 5);
  });

  test('unsafe storage host is rejected without sending any file', () async {
    api.httpClientAdapter = _Adapter(
        (_, __) async => _json(_prepared(host: 'attacker.example.test')));
    await expectLater(
        service().upload(directory.path, cancelToken: CancelToken()),
        throwsA(isA<CalibrationUploadException>()));
    expect(storageCalls, isEmpty);
  });

  test('validates all targets and rejects duplicates before first upload',
      () async {
    final response = _prepared();
    final files = response['files'] as List;
    files[4] = files[0];
    api.httpClientAdapter = _Adapter((_, __) async => _json(response));
    await expectLater(
        service().upload(directory.path, cancelToken: CancelToken()),
        throwsA(isA<CalibrationUploadException>()));
    expect(storageCalls, isEmpty);
  });

  test('pre-cancelled request does not send and keeps files', () async {
    final token = CancelToken()..cancel();
    await expectLater(
        service().upload(directory.path, cancelToken: token),
        throwsA(isA<DioException>()
            .having(CancelToken.isCancel, 'cancelled', isTrue)));
    expect(apiCalls, isEmpty);
    expect(await File('${directory.path}/view_front.jpg').exists(), isTrue);
  });

  test('HTTP redirect is not followed and does not acknowledge upload',
      () async {
    api.httpClientAdapter =
        _Adapter((_, __) async => ResponseBody.fromString('', 302, headers: {
              'location': ['https://attacker.example.test']
            }));
    await expectLater(
        service().upload(directory.path, cancelToken: CancelToken()),
        throwsA(isA<CalibrationUploadException>()));
    expect(storageCalls, isEmpty);
  });

  group('fetchJob', () {
    Dio jobApi(Object body, [int status = 200]) => Dio()
      ..httpClientAdapter = _Adapter((options, _) async {
        apiCalls.add(options);
        return _json(body, status);
      });

    test('running job reports progress and sends only the bearer token',
        () async {
      api = jobApi({'status': 'running', 'progressRate': 30});
      final job = await service().fetchJob('job-1');
      expect(job.status, 'running');
      expect(job.progressRate, 30);
      expect(job.finished, isFalse);
      expect(apiCalls.single.method, 'GET');
      expect(apiCalls.single.uri.toString(),
          'https://calibration.example.test/v1/calibrations/jobs/job-1');
      expect(apiCalls.single.headers['Authorization'], 'Bearer user-token');
    });

    test('done carries the real result', () async {
      api = jobApi({
        'status': 'done',
        'progressRate': 100,
        'result': {
          'stub': false,
          'smplBeta': List.filled(10, 0.0),
          'boneLengthData': {'segments': {}},
          'modelGlbUrl': 'https://photos.example.test/models/job-1.glb?sig=x',
        }
      });
      final job = await service().fetchJob('job-1');
      expect(job.finished, isTrue);
      expect(job.result!['modelGlbUrl'], contains('job-1.glb'));
    });

    test('a stub result is never accepted as done', () async {
      api = jobApi({
        'status': 'done',
        'result': {'stub': true, 'smplBeta': null, 'boneLengthData': null}
      });
      expect(service().fetchJob('job-1'),
          throwsA(isA<CalibrationUploadException>()));
    });

    test('failed keeps the error code; old servers without progressRate work',
        () async {
      api = jobApi({'status': 'failed', 'error': 'timeout'});
      final job = await service().fetchJob('job-1');
      expect(job.error, 'timeout');
      expect(job.progressRate, 0);
    });

    test('unknown status, 404 and a bad job id are errors', () async {
      api = jobApi({'status': 'COMPLETED'});
      await expectLater(service().fetchJob('job-1'),
          throwsA(isA<CalibrationUploadException>()));
      api = jobApi({'error': 'job_not_found'}, 404);
      await expectLater(
          service().fetchJob('job-1'),
          throwsA(isA<CalibrationUploadException>().having(
              (e) => e.message, 'message', contains('찾을 수 없어요'))));
      await expectLater(service().fetchJob('../uploads'),
          throwsA(isA<CalibrationUploadException>()));
    });
  });

  group('warmUp', () {
    test('posts once with only the bearer token', () async {
      await service().warmUp();
      expect(apiCalls.single.method, 'POST');
      expect(apiCalls.single.uri.toString(),
          'https://calibration.example.test/v1/calibrations/warmup');
      expect(apiCalls.single.headers['Authorization'], 'Bearer user-token');
      expect(storageCalls, isEmpty);
    });

    test('no token, no config or a server error: no throw', () async {
      await service(token: null).warmUp();
      await service(config: const CalibrationUploadConfig()).warmUp();
      expect(apiCalls, isEmpty);
      api = Dio()
        ..httpClientAdapter = _Adapter((options, _) async {
          apiCalls.add(options);
          return _json({'detail': 'Not Found'}, 404);
        });
      await service().warmUp();
      expect(apiCalls, hasLength(1));
    });
  });
}
