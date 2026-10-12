import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/user_model.dart';

/// Spring Boot Auth Service (Replacing Firebase Auth & Firestore)
class AuthService {
  final ApiClient _apiClient;

  AuthService(this._apiClient);

  /// Authenticate user via Spring Boot REST API
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      '/auth/login',
      data: {
        'email': email.trim(),
        'password': password,
      },
    );

    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      final token = data['token'] as String?;
      if (token != null) {
        _apiClient.setAuthToken(token);
      }
      _apiClient.setRefreshToken(data['refreshToken'] as String?);
      final userJson = data['user'] as Map<String, dynamic>? ?? data;
      return UserModel.fromJson(userJson);
    } else {
      throw ApiException('Login failed', statusCode: response.statusCode);
    }
  }

  /// Register new user in Spring Boot REST API
  Future<UserModel> signUp({
    required String username,
    required String email,
    required String password,
    required String name,
    required String phoneNumber, // 010-1234-5678
    required String birthDate, // 1998-05-15
    bool termsAgreed = true,
  }) async {
    final response = await _apiClient.post(
      '/auth/signup',
      data: {
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
        'name': name,
        'phoneNumber': phoneNumber,
        'birthDate': birthDate,
        'termsAgreed': termsAgreed,
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.data as Map<String, dynamic>;
      final token = data['token'] as String?;
      if (token != null) {
        _apiClient.setAuthToken(token);
      }
      _apiClient.setRefreshToken(data['refreshToken'] as String?);
      final userJson = data['user'] as Map<String, dynamic>? ?? data;
      return UserModel.fromJson(userJson);
    } else {
      throw ApiException('Sign up failed', statusCode: response.statusCode);
    }
  }

  /// 아이디 사용 가능 여부. 응답: {"available": bool, "message": String}
  Future<bool> checkUsername(String username) async {
    final response = await _apiClient.get(
      '/auth/check-username',
      queryParameters: {'username': username.trim()},
    );
    final data = response.data as Map<String, dynamic>;
    return (data['available'] ?? data['isAvailable']) == true;
  }

  /// 아이디/비밀번호 찾기용 이메일 인증번호 발송 (6자리, 5분 유효).
  Future<void> requestEmailVerification(String email) async {
    await _apiClient.post(
      '/auth/verify-email/request',
      data: {'email': email.trim()},
      // 서버가 메일을 다 보낸 뒤에 응답해서 3~4초 넘게 걸린다. 기본 5초로 끊으면
      // 메일은 가는데 앱은 연결 실패로 보이므로 이 요청만 길게 기다린다.
      options: Options(receiveTimeout: _emailSendTimeout),
    );
  }

  static const Duration _emailSendTimeout = Duration(seconds: 30);

  /// 인증번호 확인. 응답: {"success": bool, "message": String}
  /// (예전 서버 응답의 "verified" 도 같이 받는다)
  /// [token]: 비밀번호 재설정에 쓰는 일회용 인증 토큰 (서버가 아직 안 주면 null).
  Future<({bool verified, String? token})> confirmEmailVerification({
    required String email,
    required String code,
  }) async {
    final response = await _apiClient.post(
      '/auth/verify-email/confirm',
      data: {'email': email.trim(), 'code': code.trim()},
    );
    final data = response.data;
    final verified =
        data is Map && (data['success'] ?? data['verified']) == true;
    final token = data is Map ? data['verificationToken'] : null;
    return (verified: verified, token: token is String ? token : null);
  }

  /// 비밀번호 재설정. 아이디와 인증된 이메일이 같은 계정일 때만 바뀐다.
  /// 아이디·이메일이 같은 계정이 아니면 서버가 404 `USER_NOT_FOUND`를 준다.
  /// (서버 미구현 — 백엔드 요청 문서 1번 계정 찾기 API)
  Future<void> resetPassword({
    required String username,
    required String email,
    required String newPassword,
    String? verificationToken,
  }) async {
    await _apiClient.post(
      '/auth/reset-password',
      data: {
        'username': username.trim(),
        'email': email.trim(),
        if (verificationToken != null) 'verificationToken': verificationToken,
        'newPassword': newPassword,
      },
    );
  }

  /// 온보딩에서 입력한 성별·키·몸무게·목표·주간 운동 횟수 저장
  Future<void> updateOnboarding({
    required String gender,
    required double heightCm,
    required double weightKg,
    required String workoutGoal,
    required int weeklyFrequency,
  }) async {
    await _apiClient.put(
      '/users/me/onboarding',
      data: {
        'gender': gender,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'workoutGoal': workoutGoal,
        'weeklyFrequency': weeklyFrequency,
      },
    );
  }

  /// 체형 촬영(사진 4장)을 끝냈다고 서버에 알린다. 서버가 오늘 날짜를 측정일로
  /// 저장하고 갱신된 사용자 정보를 돌려준다.
  Future<UserModel> recordBodyScan({String? sessionPath}) async {
    final response = await _apiClient.post(
      '/users/me/body-scans',
      data: {if (sessionPath != null) 'bodyScanLocalPath': sessionPath},
    );
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// 로그인·회원가입으로 받은 현재 토큰 (기기에 저장할 때 쓴다)
  String? get authToken => _apiClient.authToken;

  /// 로그인·회원가입으로 받은 리프레시 토큰 (기기에 저장할 때 쓴다)
  String? get refreshToken => _apiClient.refreshToken;

  /// 기기에 저장해 둔 토큰으로 서버 인증 상태를 되살리거나(값) 지운다(null).
  void restoreAuthToken(String? token, {String? refreshToken}) {
    _apiClient.setAuthToken(token);
    _apiClient.setRefreshToken(refreshToken);
  }

  /// 액세스 토큰이 만료돼 자동으로 갱신되면 새 토큰을 넘긴다.
  set onTokensRefreshed(
          void Function(String accessToken, String? refreshToken)? callback) =>
      _apiClient.onTokensRefreshed = callback;

  /// 리프레시 토큰까지 만료돼 다시 로그인해야 할 때 불린다.
  set onSessionExpired(void Function()? callback) =>
      _apiClient.onSessionExpired = callback;

  /// Fetch current user profile from Spring Boot server
  Future<UserModel> fetchUserProfile() async {
    final response = await _apiClient.get('/users/me');
    if (response.statusCode == 200) {
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } else {
      throw ApiException('Failed to fetch user profile', statusCode: response.statusCode);
    }
  }

  /// Save or update user profile data
  Future<void> saveUserData(UserModel user) async {
    await _apiClient.put(
      '/users/me',
      data: user.toUpdateJson(),
    );
  }

  /// Delete current user account from Spring Boot backend
  Future<void> deleteAccount() async {
    await _apiClient.delete('/users/me');
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(apiClientProvider));
});