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
    required String email,
    required String password,
    required String name,
    bool termsAgreed = true,
    bool privacyAgreed = true,
    DateTime? birthDate,
    String? gender,
    double? heightCm,
    double? weightKg,
    String? workoutGoal,
  }) async {
    final response = await _apiClient.post(
      '/auth/signup',
      data: {
        'username': email.trim(),
        'email': email.trim(),
        'password': password,
        'name': name,
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