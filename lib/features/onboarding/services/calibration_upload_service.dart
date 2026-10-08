import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// Independent of the existing Spring API. No endpoint means no network request.
class CalibrationUploadConfig {
  const CalibrationUploadConfig({
    this.apiBaseUrl = '',
    this.storageHosts = const [],
  });

  factory CalibrationUploadConfig.fromEnvironment() => CalibrationUploadConfig(
        apiBaseUrl: const String.fromEnvironment('CALIBRATION_API_BASE_URL'),
        storageHosts: const String.fromEnvironment('CALIBRATION_STORAGE_HOSTS')
            .split(',')
            .map((host) => host.trim().toLowerCase())
            .where((host) => host.isNotEmpty)
            .toList(),
      );

  final String apiBaseUrl;
  final List<String> storageHosts;

  String? get configurationIssue {
    if (apiBaseUrl.isEmpty) return '서버리스 업로드 주소가 아직 설정되지 않았어요.';
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null || !_secure(uri) || uri.hasQuery || uri.hasFragment) {
      return '업로드 API 주소는 쿼리 없는 HTTPS 주소여야 해요.';
    }
    if (storageHosts.isEmpty) return '허용할 사진 저장소 호스트를 설정해 주세요.';
    return null;
  }

  static bool _secure(Uri uri) =>
      uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;

  Uri api(String path) =>
      Uri.parse('${apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/$path');

  bool allowsStorage(Uri uri) =>
      _secure(uri) &&
      !uri.hasFragment &&
      uri.port == 443 &&
      storageHosts.any((host) => host.toLowerCase() == uri.host.toLowerCase());
}

class CalibrationUploadException implements Exception {
  const CalibrationUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CalibrationUploadFile {
  const CalibrationUploadFile(
      this.name, this.file, this.sizeBytes, this.contentType);
  final String name;
  final File file;
  final int sizeBytes;
  final String contentType;

  Map<String, Object> toJson() => {
        'name': name,
        'sizeBytes': sizeBytes,
        'contentType': contentType,
      };
}

/// Exactly the native capture bundle. Debug logs and arbitrary paths never upload.
class CalibrationBundle {
  CalibrationBundle._(this.directory, this.sessionId, this.files);
  static const viewNames = ['front', 'rightfront', 'back', 'leftfront'];
  final Directory directory;
  final String sessionId;
  final List<CalibrationUploadFile> files;
  int get totalBytes => files.fold(0, (sum, file) => sum + file.sizeBytes);

  static Future<CalibrationBundle> load(String path) async {
    try {
      final directory = Directory(await Directory(path).resolveSymbolicLinks());
      Future<CalibrationUploadFile> checkedFile(
          String name, String type, int maxBytes) async {
        final file = File('${directory.path}/$name');
        // A session cannot trick us into sending a different file through a symlink.
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await file.resolveSymbolicLinks() != file.path) {
          throw const CalibrationUploadException(
              '촬영 파일이 없거나 올바른 파일이 아니에요. 다시 촬영해 주세요.');
        }
        final length = await file.length();
        if (length == 0 || length > maxBytes) {
          throw const CalibrationUploadException('촬영 파일 크기가 허용 범위를 벗어났어요.');
        }
        return CalibrationUploadFile(name, file, length, type);
      }

      final manifest =
          await checkedFile('manifest.json', 'application/json', 1024 * 1024);
      final data = jsonDecode(await manifest.file.readAsString());
      if (data is! Map ||
          data['schemaVersion'] != 1 ||
          data['keypointFormat'] != 'coco17_pixel_unmirrored') {
        throw const FormatException('Unsupported calibration manifest');
      }
      final id = data['sessionId'];
      if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
        throw const FormatException('Invalid session ID');
      }
      for (final field in ['imageWidth', 'imageHeight', 'userHeightCm']) {
        final value = data[field];
        if (value is! num || !value.isFinite || value <= 0) {
          throw const FormatException('Invalid capture dimensions');
        }
      }
      final views = data['views'];
      if (views is! List || views.length != 4) {
        throw const FormatException('Four views required');
      }
      final labels = <String>{};
      for (final view in views) {
        if (view is! Map ||
            !viewNames.contains(view['label']) ||
            !labels.add(view['label'] as String) ||
            view['file'] != 'view_${view['label']}.jpg') {
          throw const FormatException('Invalid view mapping');
        }
        final points = view['keypoints'];
        if (points is! List ||
            points.length != 17 ||
            points.any((point) =>
                point is! List ||
                point.length != 3 ||
                point.any((v) => v is! num || !v.isFinite))) {
          throw const FormatException('Invalid COCO17 keypoints');
        }
      }
      final files = <CalibrationUploadFile>[manifest];
      for (final view in viewNames) {
        files.add(await checkedFile(
            'view_$view.jpg', 'image/jpeg', 25 * 1024 * 1024));
      }
      return CalibrationBundle._(directory, id, List.unmodifiable(files));
    } on CalibrationUploadException {
      rethrow;
    } on FileSystemException {
      throw const CalibrationUploadException(
          '촬영 파일을 읽을 수 없어요. 사진 4장을 다시 촬영해 주세요.');
    } on FormatException {
      throw const CalibrationUploadException(
          '촬영 메타데이터가 올바르지 않아요. 사진 4장을 다시 촬영해 주세요.');
    }
  }
}

enum CalibrationUploadStage {
  validating,
  requesting,
  uploading,
  confirming,
  accepted
}

class CalibrationUploadProgress {
  const CalibrationUploadProgress(this.stage,
      {this.sentBytes = 0, this.totalBytes = 0});
  final CalibrationUploadStage stage;
  final int sentBytes;
  final int totalBytes;
  double get fraction =>
      totalBytes == 0 ? 0 : (sentBytes / totalBytes).clamp(0, 1);
}

class CalibrationUploadReceipt {
  const CalibrationUploadReceipt(this.sessionId, this.jobId);
  final String sessionId;
  final String jobId;
}

/// Prepare (small JSON) → signed storage PUTs → acknowledge/queue analysis.
/// This does NOT claim the server-side body reconstruction has completed.
class CalibrationUploadService {
  CalibrationUploadService({
    required this.config,
    required this.tokenProvider,
    Dio? api,
    Dio? storage,
  })  : _api = api ?? Dio(),
        _storage = storage ?? Dio();

  final CalibrationUploadConfig config;
  final Future<String?> Function() tokenProvider;
  // Separate clients: application Authorization must NEVER reach the signed URL.
  final Dio _api;
  final Dio _storage;

  Future<CalibrationUploadReceipt> upload(
    String sessionPath, {
    required CancelToken cancelToken,
    void Function(CalibrationUploadProgress)? onProgress,
  }) async {
    final issue = config.configurationIssue;
    if (issue != null) throw CalibrationUploadException(issue);
    void emit(CalibrationUploadStage stage, [int sent = 0, int total = 0]) =>
        onProgress?.call(CalibrationUploadProgress(stage,
            sentBytes: sent, totalBytes: total));
    try {
      emit(CalibrationUploadStage.validating);
      final bundle = await CalibrationBundle.load(sessionPath);
      final token = await tokenProvider();
      if (token == null || token.isEmpty) {
        throw const CalibrationUploadException(
            '로그인 후 다시 전송해 주세요. 사진은 기기에 보관돼 있어요.');
      }
      final apiOptions = Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Idempotency-Key': bundle.sessionId
        },
        contentType: Headers.jsonContentType,
        followRedirects: false,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      );
      _api.options.connectTimeout = const Duration(seconds: 10);
      _storage.options.connectTimeout = const Duration(seconds: 10);
      emit(CalibrationUploadStage.requesting);
      final prepared = await _api.postUri<dynamic>(
        config.api('calibrations/uploads'),
        data: {
          'schemaVersion': 1,
          'clientSessionId': bundle.sessionId,
          'files': bundle.files.map((file) => file.toJson()).toList()
        },
        options: apiOptions,
        cancelToken: cancelToken,
      );
      final body = _object(prepared.data);
      String jobId;
      if (body['status'] == 'accepted') {
        // Authenticated, idempotent acknowledgement after a lost response/restart.
        jobId = _id(body['jobId']);
      } else {
        if (body['status'] != 'upload_required') {
          throw const FormatException('Invalid prepare status');
        }
        final uploadId = _id(body['uploadId']);
        final targets = body['files'];
        if (targets is! List || targets.length != bundle.files.length) {
          throw const FormatException('Missing upload targets');
        }
        final byName = <String, Map<String, dynamic>>{};
        // Validate the WHOLE response before sending any photo.
        for (final target in targets) {
          final map = _object(target);
          final name = map['name'];
          final rawUrl = map['url'];
          if (name is! String ||
              byName.containsKey(name) ||
              rawUrl is! String ||
              !bundle.files.any((file) => file.name == name) ||
              map['method'] != 'PUT') {
            throw const FormatException('Invalid upload target');
          }
          final uri = Uri.tryParse(rawUrl);
          if (uri == null || !config.allowsStorage(uri)) {
            throw const CalibrationUploadException(
                '허용되지 않은 업로드 저장소예요. 서버 설정을 확인해 주세요.');
          }
          // Contract fixes Content-Type/Length; don't forward arbitrary server headers.
          byName[name] = map;
        }
        var sent = 0;
        for (final file in bundle.files) {
          emit(CalibrationUploadStage.uploading, sent, bundle.totalBytes);
          await _storage.putUri<dynamic>(
            Uri.parse(byName[file.name]!['url'] as String),
            data: file.file.openRead(),
            options: Options(
              headers: {HttpHeaders.contentLengthHeader: file.sizeBytes},
              contentType: file.contentType,
              responseType: ResponseType.plain,
              followRedirects: false,
              sendTimeout: const Duration(minutes: 2),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 300,
            ),
            cancelToken: cancelToken,
            onSendProgress: (count, _) => emit(CalibrationUploadStage.uploading,
                sent + count.clamp(0, file.sizeBytes), bundle.totalBytes),
          );
          sent += file.sizeBytes;
        }
        emit(CalibrationUploadStage.confirming, sent, bundle.totalBytes);
        final completed = await _api.postUri<dynamic>(
          config.api('calibrations/uploads/$uploadId/complete'),
          data: {'clientSessionId': bundle.sessionId},
          options: apiOptions,
          cancelToken: cancelToken,
        );
        final result = _object(completed.data);
        if (result['status'] != 'accepted') {
          throw const FormatException('Missing acknowledgement');
        }
        jobId = _id(result['jobId']);
      }
      // Save only a receipt, NEVER tokens, signed URLs or another copy of the photos.
      final receipt = File('${bundle.directory.path}/upload_receipt.json');
      final temporary = File('${receipt.path}.tmp');
      await temporary.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'clientSessionId': bundle.sessionId,
            'jobId': jobId,
            'status': 'accepted',
            'apiBaseUrl': config.apiBaseUrl,
            'acceptedAt': DateTime.now().toUtc().toIso8601String(),
          }),
          flush: true);
      await temporary.rename(receipt.path);
      emit(CalibrationUploadStage.accepted, bundle.totalBytes,
          bundle.totalBytes);
      return CalibrationUploadReceipt(bundle.sessionId, jobId);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      final status = error.response?.statusCode;
      // Don't surface errors containing signed URLs or authorization headers.
      if (status == 401) {
        throw const CalibrationUploadException(
            '로그인이 만료됐어요. 다시 로그인한 뒤 전송해 주세요.');
      }
      throw const CalibrationUploadException(
          '전송을 완료하지 못했어요. 사진은 보관돼 있으니 연결을 확인하고 다시 시도해 주세요.');
    } on FormatException {
      throw const CalibrationUploadException(
          '업로드 서버 응답 형식이 올바르지 않아요. API 명세를 확인해 주세요.');
    } on FileSystemException {
      throw const CalibrationUploadException(
          '로컬 전송 기록을 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Object required');
    }
    return value;
  }

  static String _id(dynamic value) {
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
      throw const FormatException('Invalid identifier');
    }
    return value;
  }

  void close() {
    _api.close(force: true);
    _storage.close(force: true);
  }
}

final calibrationUploadServiceProvider =
    Provider<CalibrationUploadService>((ref) {
  final auth = ref.watch(apiClientProvider);
  final service = CalibrationUploadService(
    config: CalibrationUploadConfig.fromEnvironment(),
    tokenProvider: () async => auth.authToken,
  );
  ref.onDispose(service.close);
  return service;
});
