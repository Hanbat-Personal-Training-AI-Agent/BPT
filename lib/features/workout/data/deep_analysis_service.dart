import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../services/local_storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../onboarding/services/calibration_upload_service.dart';

class DeepAnalysisCapture {
  const DeepAnalysisCapture(this.videoPath, this.manifest);
  final String videoPath;
  final Map<String, dynamic> manifest;
  String get sessionId => manifest['sessionId'] as String;
  String get exerciseId => manifest['exerciseId'] as String;

  static DeepAnalysisCapture? fromSet(Map record, String exerciseId) {
    final path = record['videoLocalPath'];
    final metadata = record['deepAnalysis'];
    if (path is! String ||
        path.isEmpty ||
        metadata is! Map ||
        metadata['sessionId'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$')
            .hasMatch(metadata['sessionId'] as String) ||
        metadata['reps'] is! List ||
        (metadata['reps'] as List).isEmpty) {
      return null;
    }
    return DeepAnalysisCapture(path, {
      ...metadata.cast<String, dynamic>(),
      'exerciseId': exerciseId,
    });
  }
}

class DeepAnalysisJob {
  const DeepAnalysisJob(this.status, this.progress,
      {this.result, this.error, this.retryable = false});
  final String status;
  final int progress;
  final Map<String, dynamic>? result;
  final String? error;
  final bool retryable;

  factory DeepAnalysisJob.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (!{'queued', 'running', 'done', 'failed'}.contains(status)) {
      throw const FormatException('작업 상태가 올바르지 않아요.');
    }
    final result = json['result'] as Map<String, dynamic>?;
    if (status == 'done' &&
        (result?['report'] is! Map ||
            result?['report']['schemaVersion'] != 1 ||
            result?['report']['reps'] is! List ||
            result?['report']['timeline'] is! List ||
            result?['report']['summary'] is! Map ||
            result?['videoUrl'] is! String)) {
      throw const FormatException('분석 결과가 올바르지 않아요.');
    }
    return DeepAnalysisJob(status as String,
        ((json['progressRate'] as num?) ?? 0).clamp(0, 100).toInt(),
        result: result,
        error: json['error'] as String?,
        retryable: json['retryable'] == true);
  }
}

class DeepAnalysisService {
  DeepAnalysisService(
      {required this.config,
      required this.tokenProvider,
      this.refreshToken,
      this.userId,
      this.sessionGuard,
      Dio? api,
      Dio? storage})
      : _api = api ?? Dio(),
        _storage = storage ?? Dio() {
    _api.options.connectTimeout = const Duration(seconds: 10);
    _storage.options.connectTimeout = const Duration(seconds: 10);
    _api.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (!isCurrent) return handler.reject(_sessionCancelled(request));
      handler.next(request);
    }, onResponse: (response, handler) {
      if (!isCurrent) {
        return handler.reject(_sessionCancelled(response.requestOptions));
      }
      handler.next(response);
    }, onError: (error, handler) async {
      final request = error.requestOptions;
      if (!isCurrent) return handler.reject(_sessionCancelled(request));
      final authorization = request.headers['Authorization'];
      if (!isCurrent ||
          request.cancelToken?.isCancelled == true ||
          error.response?.statusCode != 401 ||
          refreshToken == null ||
          request.extra['deepAuthRetried'] == true ||
          authorization is! String ||
          !authorization.startsWith('Bearer ')) {
        return handler.next(error);
      }
      try {
        final token = await refreshToken!(authorization.substring(7));
        if (!isCurrent ||
            request.cancelToken?.isCancelled == true ||
            token == null) {
          return handler.next(error);
        }
        final response = await _api.fetch<dynamic>(request.copyWith(
          headers: {...request.headers, 'Authorization': 'Bearer $token'},
          extra: {...request.extra, 'deepAuthRetried': true},
        ));
        handler.resolve(response);
      } on DioException catch (retryError) {
        handler.next(retryError);
      } catch (_) {
        handler.next(error);
      }
    }));
    _storage.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) {
      if (!isCurrent) return handler.reject(_sessionCancelled(request));
      handler.next(request);
    }));
  }

  final CalibrationUploadConfig config;
  final Future<String?> Function() tokenProvider;
  final Future<String?> Function(String rejectedToken)? refreshToken;
  final String? userId;
  final bool Function()? sessionGuard;
  final Dio _api;
  // 로그인 인증 헤더는 서명 URL 전송 클라이언트에 넣지 않는다.
  final Dio _storage;
  bool _closed = false;
  bool get isCurrent {
    if (_closed) return false;
    try {
      return sessionGuard?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  static DioException _sessionCancelled(RequestOptions request) => DioException(
      requestOptions: request,
      type: DioExceptionType.cancel,
      error: ApiException('Account session changed',
          code: ApiClient.sessionChangedCode));
  String get _historyKey => 'deep_analysis:$userId:${config.apiBaseUrl}';

  Future<Options> _options([String? session]) async {
    final issue = config.configurationIssue;
    if (issue != null) throw CalibrationUploadException(issue);
    final token = await tokenProvider();
    if (!isCurrent || token == null || token.isEmpty) {
      throw const CalibrationUploadException('로그인 후 다시 시도해 주세요.');
    }
    return Options(
        headers: {
          'Authorization': 'Bearer $token',
          if (session != null) 'Idempotency-Key': session
        },
        followRedirects: false,
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300);
  }

  static String _id(dynamic value) {
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
      throw const FormatException('작업 번호가 올바르지 않아요.');
    }
    return value;
  }

  Uri _storageUri(dynamic value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null || !config.allowsStorage(uri)) {
      throw const FormatException('허용되지 않은 저장소 주소예요.');
    }
    return uri;
  }

  Uri videoUri(Map<String, dynamic> result) => _storageUri(result['videoUrl']);

  Future<bool> canUpload(DeepAnalysisCapture capture) async {
    if (!isCurrent) return false;
    final size = await File(capture.videoPath).length();
    if (!isCurrent) return false;
    if (size <= 0 || size > 32 * 1024 * 1024) {
      throw const FormatException('영상 크기가 제한을 넘었어.');
    }
    final connections = await Connectivity().checkConnectivity();
    if (!isCurrent) return false;
    if (connections.contains(ConnectivityResult.none)) return false;
    return connections.contains(ConnectivityResult.wifi) ||
        size <= 8 * 1024 * 1024;
  }

  Future<String> upload(DeepAnalysisCapture capture, CancelToken cancel,
      {void Function(String)? onProgress}) async {
    final options = await _options(_id(capture.sessionId));
    final video = File(capture.videoPath);
    if (!await video.exists()) {
      throw FileSystemException('세트 영상이 기기에 남아 있지 않아요.', video.path);
    }
    final size = await video.length();
    final metadata = utf8.encode(jsonEncode(capture.manifest));
    if (size <= 0 || size > 32 * 1024 * 1024 || metadata.length > 256 * 1024) {
      throw const FormatException('60초 이내의 세트 영상만 분석할 수 있어요.');
    }
    final sizes = {'video.mp4': size, 'reps.json': metadata.length};
    final types = {'video.mp4': 'video/mp4', 'reps.json': 'application/json'};
    onProgress?.call('업로드 준비 중이에요.');
    final prepared = (await _api.postUri<Map<String, dynamic>>(
      config.api('deep-analysis/uploads'),
      options: options,
      cancelToken: cancel,
      data: {
        'schemaVersion': 1,
        'clientSessionId': capture.sessionId,
        'files': sizes.entries
            .map((e) => {
                  'name': e.key,
                  'sizeBytes': e.value,
                  'contentType': types[e.key]
                })
            .toList()
      },
    ))
        .data!;
    String jobId;
    if (prepared['status'] == 'accepted') {
      jobId = _id(prepared['jobId']);
    } else {
      if (prepared['status'] != 'upload_required') {
        throw const FormatException();
      }
      final uploadId = _id(prepared['uploadId']);
      final targets = prepared['files'];
      if (targets is! List || targets.length != 2) {
        throw const FormatException();
      }
      final urls = <String, Uri>{};
      for (final target in targets) {
        if (target is! Map ||
            !sizes.containsKey(target['name']) ||
            urls.containsKey(target['name']) ||
            target['method'] != 'PUT') {
          throw const FormatException();
        }
        urls[target['name'] as String] = _storageUri(target['url']);
      }
      for (final name in sizes.keys) {
        onProgress
            ?.call(name == 'video.mp4' ? '세트 영상을 올리고 있어요.' : '반복 기록을 올리고 있어요.');
        await _storage.putUri<dynamic>(urls[name]!,
            data:
                name == 'video.mp4' ? video.openRead() : Stream.value(metadata),
            cancelToken: cancel,
            options: Options(
                contentType: types[name],
                headers: {HttpHeaders.contentLengthHeader: sizes[name]},
                followRedirects: false,
                responseType: ResponseType.plain,
                sendTimeout: const Duration(minutes: 3),
                receiveTimeout: const Duration(seconds: 30),
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 300));
      }
      final completed = (await _api.postUri<Map<String, dynamic>>(
        config.api('deep-analysis/uploads/$uploadId/complete'),
        data: {'clientSessionId': capture.sessionId},
        options: options,
        cancelToken: cancel,
      ))
          .data!;
      if (completed['status'] != 'accepted') throw const FormatException();
      jobId = _id(completed['jobId']);
    }
    return jobId;
  }

  Future<List<Map<String, dynamic>>> loadQueue() async {
    if (!isCurrent || userId == null) return [];
    final prefs = await SharedPreferences.getInstance();
    if (!isCurrent) return [];
    return (prefs.getStringList(_historyKey) ?? [])
        .map((row) => (jsonDecode(row) as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> saveQueue(List<Map<String, dynamic>> rows) async {
    if (!isCurrent || userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await LocalStorageService(prefs).serializeSessionWrite(() async {
      if (!isCurrent) return;
      await prefs.setStringList(_historyKey, rows.map(jsonEncode).toList());
    });
  }

  Future<String> retryJob(String jobId, CancelToken cancel) async {
    final response = await _api.postUri<Map<String, dynamic>>(
        config.api('deep-analysis/jobs/${_id(jobId)}/retry'),
        options: await _options(),
        cancelToken: cancel);
    return _id(response.data?['jobId']);
  }

  Future<DeepAnalysisJob> fetchJob(String jobId, CancelToken cancel) async {
    final response = await _api.getUri<Map<String, dynamic>>(
        config.api('deep-analysis/jobs/${_id(jobId)}'),
        options: await _options(),
        cancelToken: cancel);
    return DeepAnalysisJob.fromJson(response.data!);
  }

  Future<File> downloadVideo(String jobId, CancelToken cancel) async {
    // 1시간 만료 URL은 다운로드 버튼을 누를 때 갱신한다.
    final job = await fetchJob(jobId, cancel);
    if (job.status != 'done') throw const FormatException();
    final uri = _storageUri(job.result?['videoUrl']);
    final directory = await Directory.systemTemp.createTemp(
        LocalStorageService.deepAnalysisTempPrefix(userId ?? 'anonymous'));
    final file = File('${directory.path}/심층분석.mp4');
    try {
      await _storage.downloadUri(uri, file.path,
          cancelToken: cancel,
          options: Options(
              followRedirects: false,
              receiveTimeout: const Duration(minutes: 3),
              validateStatus: (status) => status == 200));
      if (!isCurrent) throw const CalibrationUploadException('로그인 상태가 바뀌었어요.');
      return file;
    } catch (_) {
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
      } on FileSystemException {
        // Account cleanup may already have removed this generated download.
      }
      rethrow;
    }
  }

  void close() {
    _closed = true;
    _api.close(force: true);
    _storage.close(force: true);
  }
}

final deepAnalysisServiceProvider = Provider<DeepAnalysisService>((ref) {
  final api = ref.watch(apiClientProvider);
  ref.watch(authSessionIdentityProvider);
  final session = ref.read(authNotifierProvider).captureSession();
  bool active() => session?.isCurrent ?? false;
  final service = DeepAnalysisService(
      config: CalibrationUploadConfig.fromEnvironment(),
      tokenProvider: () async => active() ? api.authToken : null,
      sessionGuard: active,
      refreshToken: (rejected) async {
        if (!active()) return null;
        final token =
            await api.refreshAccessToken(rejected, sessionGuard: active);
        return active() ? token : null;
      },
      userId: session?.userId);
  ref.onDispose(service.close);
  return service;
});
