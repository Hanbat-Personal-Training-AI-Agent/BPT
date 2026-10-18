import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Exceptions handled across Spring Boot REST API calls
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic errorData;

  /// 백엔드 에러 코드 (예: EMAIL_ALREADY_EXISTS).
  final String? code;

  ApiException(this.message, {this.statusCode, this.errorData, this.code});

  @override
  String toString() => 'ApiException: [$statusCode] $message';
}

class NetworkException extends ApiException {
  NetworkException(
      [super.message = 'Network connection unavailable or timed out']);
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(
      [super.message = 'Unauthorized session. Please login again.',
      String? code])
      : super(statusCode: 401, code: code);
}

class ServerException extends ApiException {
  ServerException(
      [super.message = 'Spring Boot Server error occurred',
      int? statusCode,
      String? code])
      : super(statusCode: statusCode, code: code);
}

/// Base API Config
class ApiConfig {
  /// Default Spring Boot backend URL (deployed server).
  /// Override for local dev with --dart-define=API_BASE_URL=...
  /// (Android Emulator: http://10.0.2.2:8080/api/v1, iOS Simulator: http://localhost:8080/api/v1)
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://151.145.79.106:8080/api/v1',
  );
  static const int connectTimeoutMs = 5000;
  static const int receiveTimeoutMs = 5000;
  static const int sendTimeoutMs = 5000;
}

/// Spring Boot REST API Client built on Dio
class ApiClient {
  late final Dio _dio;
  String? _authToken;
  String? _refreshToken;

  /// 진행 중인 토큰 갱신. 여러 요청이 동시에 만료돼도 갱신은 한 번만 한다.
  Future<bool>? _refreshing;

  /// 토큰을 갱신하면 새 액세스·리프레시 토큰을 넘긴다 (기기에 저장용).
  void Function(String accessToken, String? refreshToken)? onTokensRefreshed;

  /// 리프레시 토큰까지 만료돼 다시 로그인해야 할 때 불린다.
  void Function()? onSessionExpired;

  ApiClient({String? baseUrl, Dio? refreshDio}) {
    _refreshDio = refreshDio ?? _createDio(baseUrl);
    _dio = _createDio(baseUrl);

    _dio.interceptors.addAll([
      // 디버그 빌드에서만 모든 API 요청/응답을 콘솔에 찍는다. (배포 빌드는 출력 없음)
      if (kDebugMode) _ApiDebugLogInterceptor(),
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_authToken != null && _authToken!.isNotEmpty) {
            options.headers[HttpHeaders.authorizationHeader] =
                'Bearer $_authToken';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // 액세스 토큰 만료(서버는 403, 일부 401) → 한 번만 갱신하고 원래 요청을 다시 보낸다.
          if (_shouldRefresh(error) &&
              (_sentWithOldToken(error) || await _refreshTokens())) {
            try {
              final options = error.requestOptions..extra[_retriedKey] = true;
              options.headers[HttpHeaders.authorizationHeader] =
                  'Bearer $_authToken';
              return handler.resolve(await _dio.fetch(options));
            } on DioException catch (e) {
              error = e;
            }
          }
          final customException = error.error is ApiException
              ? error.error as ApiException
              : _handleDioError(error);
          return handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              error: customException,
              type: error.type,
              response: error.response,
            ),
          );
        },
      ),
    ]);
    if (kDebugMode) _refreshDio.interceptors.add(_ApiDebugLogInterceptor());
  }

  /// 토큰 갱신 전용. 갱신 요청이 다시 갱신을 부르지 않게 갱신 인터셉터 없이 따로 둔다.
  late final Dio _refreshDio;

  static const _retriedKey = '_tokenRefreshRetried';

  /// 다른 계정의 운동 기록에 접근했을 때 백엔드가 주는 403 에러 코드.
  static const sessionAccessDenied = 'SESSION_ACCESS_DENIED';

  static Dio _createDio(String? baseUrl) => Dio(
        BaseOptions(
          baseUrl: baseUrl ?? ApiConfig.baseUrl,
          connectTimeout:
              const Duration(milliseconds: ApiConfig.connectTimeoutMs),
          receiveTimeout:
              const Duration(milliseconds: ApiConfig.receiveTimeoutMs),
          sendTimeout: const Duration(milliseconds: ApiConfig.sendTimeoutMs),
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.acceptHeader: 'application/json',
          },
        ),
      );

  void setAuthToken(String? token) {
    _authToken = token;
  }

  void setRefreshToken(String? token) {
    _refreshToken = token;
  }

  String? get refreshToken => _refreshToken;

  bool _shouldRefresh(DioException error) {
    final status = error.response?.statusCode;
    return (status == 401 || status == 403) &&
        _refreshToken != null &&
        _authToken != null &&
        error.requestOptions.extra[_retriedKey] != true &&
        // 로그인·가입·갱신 같은 인증 API의 401은 토큰 만료가 아니다.
        !error.requestOptions.path.startsWith('/auth/') &&
        // 다른 계정의 기록에 접근한 403도 토큰 만료가 아니다.
        _errorCode(error) != sessionAccessDenied;
  }

  /// 백엔드 에러 응답({success: false, error: {code, message}})의 code.
  static String? _errorCode(DioException error) {
    final data = error.response?.data;
    final body = data is Map ? data['error'] : null;
    return body is Map ? body['code']?.toString() : null;
  }

  /// 이 요청을 보낸 뒤 다른 요청이 이미 토큰을 갱신했으면 갱신 없이 다시 보내면 된다.
  bool _sentWithOldToken(DioException error) =>
      error.requestOptions.headers[HttpHeaders.authorizationHeader] !=
      'Bearer $_authToken';

  /// POST /auth/refresh 로 새 토큰을 받는다. 성공하면 true.
  Future<bool> _refreshTokens() {
    return _refreshing ??= () async {
      try {
        final response = await _refreshDio.post(
          '/auth/refresh',
          data: {'refreshToken': _refreshToken},
        );
        final data = response.data;
        final access =
            data is Map ? data['accessToken'] ?? data['token'] : null;
        if (access is! String || access.isEmpty) return false;
        final refresh = data['refreshToken'];
        _authToken = access;
        if (refresh is String && refresh.isNotEmpty) _refreshToken = refresh;
        onTokensRefreshed?.call(_authToken!, _refreshToken);
        return true;
      } on DioException catch (e) {
        // 서버가 거절했으면(401·403) 리프레시 토큰도 만료 → 다시 로그인.
        // 네트워크·서버 오류면 세션은 그대로 두고 원래 에러를 돌려준다.
        final status = e.response?.statusCode;
        if (status == 401 || status == 403) {
          _authToken = null;
          _refreshToken = null;
          onSessionExpired?.call();
        }
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  String? get authToken => _authToken;

  Dio get dio => _dio;

  // GET Request
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw e.error is ApiException ? e.error! : _handleDioError(e);
    }
  }

  // POST Request
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw e.error is ApiException ? e.error! : _handleDioError(e);
    }
  }

  // PUT Request
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw e.error is ApiException ? e.error! : _handleDioError(e);
    }
  }

  // DELETE Request
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw e.error is ApiException ? e.error! : _handleDioError(e);
    }
  }

  ApiException _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return NetworkException(
            'Network timeout or connection refused (${error.message})');
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final data = error.response?.data;
        // 백엔드 에러 응답 형식: {success: false, error: {code, message}}
        final errorBody = data is Map ? data['error'] : null;
        final code = errorBody is Map ? errorBody['code']?.toString() : null;
        final message = errorBody is Map
            ? (errorBody['message'] ?? 'Server error')
            : data is Map
                ? (data['message'] ?? 'Server error')
                : 'Server error ($statusCode)';

        if (statusCode == 401 || statusCode == 403) {
          return UnauthorizedException(message.toString(), code);
        }
        return ServerException(message.toString(), statusCode, code);
      case DioExceptionType.cancel:
        return ApiException('Request cancelled');
      default:
        return ApiException(error.message ?? 'Unexpected network error');
    }
  }
}

/// 디버그 콘솔용 API 로그. 예)
///   [API] → POST /auth/login {"email":"tester","password":"***"}
///   [API] ← 200 POST /auth/login (182ms) {"token":"***","user":{...}}
///   [API] ✕ 401 POST /auth/login (95ms) INVALID_CREDENTIALS: 이메일 또는 비밀번호를...
/// 비밀번호·토큰 값은 가리고, 긴 본문은 잘라서 보여준다.
class _ApiDebugLogInterceptor extends Interceptor {
  static const _secretKeys = {
    'password',
    'token',
    'accessToken',
    'refreshToken',
  };
  static const _maxBodyLength = 800;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_apiLogStart'] = DateTime.now();
    final query =
        options.queryParameters.isEmpty ? '' : ' ${options.queryParameters}';
    final body = options.data == null ? '' : ' ${_format(options.data)}';
    debugPrint('[API] → ${options.method} ${options.path}$query$body');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    debugPrint('[API] ← ${response.statusCode} ${o.method} ${o.path}'
        '${_elapsed(o)} ${_format(response.data)}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final o = err.requestOptions;
    final status = err.response?.statusCode;
    final data = err.response?.data;
    final errorBody = data is Map ? data['error'] : null;
    final detail = errorBody is Map
        ? '${errorBody['code']}: ${errorBody['message']}'
        : data != null
            ? _format(data)
            : '${err.type.name} ${err.message ?? ''}';
    debugPrint('[API] ✕ ${status ?? '-'} ${o.method} ${o.path}'
        '${_elapsed(o)} $detail');
    handler.next(err);
  }

  String _elapsed(RequestOptions o) {
    final start = o.extra['_apiLogStart'];
    if (start is! DateTime) return '';
    return ' (${DateTime.now().difference(start).inMilliseconds}ms)';
  }

  String _format(dynamic data) {
    String text;
    try {
      text = jsonEncode(_mask(data));
    } catch (_) {
      text = data.toString();
    }
    return text.length > _maxBodyLength
        ? '${text.substring(0, _maxBodyLength)}...(${text.length}자)'
        : text;
  }

  dynamic _mask(dynamic data) {
    if (data is Map) {
      return {
        for (final e in data.entries)
          e.key.toString(): _secretKeys.contains(e.key) && e.value != null
              ? '***'
              : _mask(e.value),
      };
    }
    if (data is List) return data.map(_mask).toList();
    return data;
  }
}

/// Riverpod provider for ApiClient singleton
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});
