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
    );
  }

  /// 인증번호 확인. 응답: {"success": bool, "message": String}
  /// (예전 서버 응답의 "verified" 도 같이 받는다)
  Future<bool> confirmEmailVerification({
    required String email,
    required String code,
  }) async {
    final response = await _apiClient.post(
      '/auth/verify-email/confirm',
      data: {'email': email.trim(), 'code': code.trim()},
    );
    final data = response.data;
    return data is Map && (data['success'] ?? data['verified']) == true;
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