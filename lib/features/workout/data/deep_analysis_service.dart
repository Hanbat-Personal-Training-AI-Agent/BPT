import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
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
        metadata is! Map ||
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
      this.userId,
      Dio? api,
      Dio? storage})
      : _api = api ?? Dio(),
        _storage = storage ?? Dio() {
    _api.options.connectTimeout = const Duration(seconds: 10);
    _storage.options.connectTimeout = const Duration(seconds: 10);
  }

  final CalibrationUploadConfig config;
  final Future<String?> Function() tokenProvider;
  final String? userId;
  final Dio _api;
  // 로그인 인증 헤더는 서명 URL 전송 클라이언트에 넣지 않는다.
  final Dio _storage;
  String get _historyKey => 'deep_analysis:$userId:${config.apiBaseUrl}';

  Future<Options> _options([String? session]) async {
    final issue = config.configurationIssue;
    if (issue != null) throw CalibrationUploadException(issue);
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
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
    final size = await File(capture.videoPath).length();
    if (size <= 0 || size > 32 * 1024 * 1024) {
      throw const FormatException('영상 크기가 제한을 넘었어.');
    }
    final connections = await Connectivity().checkConnectivity();
    if (connections.contains(ConnectivityResult.none)) return false;
    return connections.contains(ConnectivityResult.wifi) ||
        size <= 8 * 1024 * 1024;
  }

  Future<String> upload(DeepAnalysisCapture capture, CancelToken cancel,
      {void Function(String)? onProgress}) async {
    final options = await _options(_id(capture.sessionId));
    final video = File(capture.videoPath);
    if (!await video.exists()) {
      throw const CalibrationUploadException('세트 영상이 기기에 남아 있지 않아요.');
    }
    final size = await video.length();
    final metadata = utf8.encode(jsonEncode(capture.manifest));
    if (size <= 0 || size > 32 * 1024 * 1024 || metadata.length > 256 * 1024) {
      throw const CalibrationUploadException('60초 이내의 세트 영상만 분석할 수 있어요.');
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
    if (userId == null) return [];
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_historyKey) ?? [])
        .map((row) => (jsonDecode(row) as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> saveQueue(List<Map<String, dynamic>> rows) async {
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, rows.map(jsonEncode).toList());
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
    final directory = await Directory.systemTemp.createTemp('bpt-deep-');
    final file = File('${directory.path}/심층분석.mp4');
    try {
      await _storage.downloadUri(uri, file.path,
          cancelToken: cancel,
          options: Options(
              followRedirects: false,
              receiveTimeout: const Duration(minutes: 3),
              validateStatus: (status) => status == 200));
      return file;
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  void close() {
    _api.close(force: true);
    _storage.close(force: true);
  }
}

final deepAnalysisServiceProvider = Provider<DeepAnalysisService>((ref) {
  final api = ref.watch(apiClientProvider);
  final service = DeepAnalysisService(
      config: CalibrationUploadConfig.fromEnvironment(),
      tokenProvider: () async => api.authToken,
      userId: ref.watch(currentUserIdProvider));
  ref.onDispose(service.close);
  return service;
});
