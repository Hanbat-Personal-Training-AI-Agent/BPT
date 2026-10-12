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
    bool privacyAgreed = true,
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
        'privacyAgreed': privacyAgreed,
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.data as Map<String, dynamic>;
      final token = data['token'] as String?;
      if (token != null) {
        _apiClient.setAuthToken(token);
      }
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

  /// 이메일 인증번호 발송 요청 (purpose: SIGN_UP, FIND_ACCOUNT 등)
  Future<Map<String, dynamic>> requestEmailVerification(String email, {String? purpose}) async {
    final response = await _apiClient.post(
      '/auth/verify-email/request',
      data: {
        'email': email.trim(),
        if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// 이메일 인증번호 확인 (verified/success 및 verificationToken 반환)
  Future<Map<String, dynamic>> confirmEmailVerification(String email, String code) async {
    final response = await _apiClient.post(
      '/auth/verify-email/confirm',
      data: {
        'email': email.trim(),
        'code': code.trim(),
      },
    );
    final data = response.data as Map<String, dynamic>;
    return data;
  }

  /// 아이디 찾기 (verificationToken 권장, email 호환 지원)
  Future<Map<String, dynamic>> findUsername({
    String? verificationToken,
    String? email,
    String? code,
  }) async {
    final response = await _apiClient.post(
      '/auth/find-username',
      data: {
        if (verificationToken != null && verificationToken.isNotEmpty)
          'verificationToken': verificationToken.trim(),
        if (email != null && email.isNotEmpty) 'email': email.trim(),
        if (code != null && code.isNotEmpty) 'code': code.trim(),
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// 비밀번호 재설정 (아이디 + 이메일 + 일회용 verificationToken)
  Future<void> resetPassword({
    required String email,
    required String newPassword,
    String? username,
    String? verificationToken,
    String? code,
  }) async {
    final response = await _apiClient.post(
      '/auth/reset-password',
      data: {
        'email': email.trim(),
        'newPassword': newPassword,
        if (username != null && username.isNotEmpty) 'username': username.trim(),
        if (verificationToken != null && verificationToken.isNotEmpty)
          'verificationToken': verificationToken.trim(),
        if (code != null && code.isNotEmpty) 'code': code.trim(),
      },
    );
    if (response.statusCode != 200) {
      throw ApiException('Password reset failed', statusCode: response.statusCode);
    }
  }

  /// 토큰 갱신 API (액세스 토큰 만료 시 새 accessToken / refreshToken 발급)
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final response = await _apiClient.post(
      '/auth/refresh',
      data: {'refreshToken': refreshToken.trim()},
    );
    final data = response.data as Map<String, dynamic>;
    final newAccessToken = data['accessToken'] ?? data['token'];
    if (newAccessToken is String && newAccessToken.isNotEmpty) {
      _apiClient.setAuthToken(newAccessToken);
    }
    return data;
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

  /// 주간 운동 목표(주 N회). 사용자 정보(/users/me)에는 없어서 대시보드의
  /// weeklyGoalCount 를 읽는다.
  Future<int?> fetchWeeklyGoal() async {
    final response = await _apiClient.get('/users/me/dashboard');
    final data = response.data;
    return data is Map ? (data['weeklyGoalCount'] as num?)?.toInt() : null;
  }

  /// 로그인·회원가입으로 받은 현재 토큰 (기기에 저장할 때 쓴다)
  String? get authToken => _apiClient.authToken;

  /// 기기에 저장해 둔 토큰으로 서버 인증 상태를 되살리거나(값) 지운다(null).
  void restoreAuthToken(String? token) => _apiClient.setAuthToken(token);

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
      data: user.toJson(),
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