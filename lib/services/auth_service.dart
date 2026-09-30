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
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(apiClientProvider));
});