import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Exceptions handled across Spring Boot REST API calls
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic errorData;

  ApiException(this.message, {this.statusCode, this.errorData});

  @override
  String toString() => 'ApiException: [$statusCode] $message';
}

class NetworkException extends ApiException {
  NetworkException([super.message = 'Network connection unavailable or timed out']);
}

class UnauthorizedException extends ApiException {
  UnauthorizedException([super.message = 'Unauthorized session. Please login again.'])
      : super(statusCode: 401);
}

class ServerException extends ApiException {
  ServerException([super.message = 'Spring Boot Server error occurred', int? statusCode])
      : super(statusCode: statusCode);
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

  ApiClient({String? baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiConfig.baseUrl,
        connectTimeout: const Duration(milliseconds: ApiConfig.connectTimeoutMs),
        receiveTimeout: const Duration(milliseconds: ApiConfig.receiveTimeoutMs),
        sendTimeout: const Duration(milliseconds: ApiConfig.sendTimeoutMs),
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.acceptHeader: 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_authToken != null && _authToken!.isNotEmpty) {
            options.headers[HttpHeaders.authorizationHeader] = 'Bearer $_authToken';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) {
          final customException = _handleDioError(error);
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
  }

  void setAuthToken(String? token) {
    _authToken = token;
  }

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
        return NetworkException('Network timeout or connection refused (${error.message})');
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final data = error.response?.data;
        final message = data is Map ? (data['message'] ?? data['error'] ?? 'Server error') : 'Server error ($statusCode)';

        if (statusCode == 401 || statusCode == 403) {
          return UnauthorizedException(message.toString());
        }
        return ServerException(message.toString(), statusCode);
      case DioExceptionType.cancel:
        return ApiException('Request cancelled');
      default:
        return ApiException(error.message ?? 'Unexpected network error');
    }
  }
}

/// Riverpod provider for ApiClient singleton
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});
