import 'package:flutter/foundation.dart' show ChangeNotifier, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../models/user_model.dart';
import '../../../services/auth_service.dart';
import '../../../services/local_storage_service.dart';

// ── Auth Notifier (Spring Boot REST API + Offline Dev Fallback) ──────────────
class AuthNotifier extends ChangeNotifier {
  final AuthService _authService;
  final LocalStorageService _storage;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _isOfflineMode = false;

  AuthNotifier(this._authService, this._storage);

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isOfflineMode => _isOfflineMode;

  /// Try restoring user session from local storage or fetching from Spring Boot API
  Future<bool> tryAutoLogin() async {
    final cachedUser = _storage.loadUser();
    final autoLogin = _storage.loadAutoLogin();

    if (cachedUser == null || !autoLogin) {
      return false;
    }

    _currentUser = cachedUser;
    notifyListeners();

    // Try background refresh from Spring Boot server
    try {
      final freshUser = await _authService.fetchUserProfile();
      _currentUser = freshUser;
      await _storage.saveUser(freshUser);
      _isOfflineMode = false;
      notifyListeners();
    } catch (_) {
      // Offline fallback: continue with cached user profile
      _isOfflineMode = true;
    }

    return true;
  }

  /// Login via Spring Boot REST API (Falls back to offline local user if server is unreachable)
  Future<void> login(
    String email,
    String password, {
    bool rememberMe = false,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _authService.login(email: email, password: password);
      _currentUser = user;
      await _storage.saveUser(user);
      await _storage.saveAutoLogin(rememberMe);
      _isOfflineMode = false;
      _error = null;
    } on NetworkException {
      // Spring Boot backend not running or unreachable -> Fallback to Offline Local Login
      _currentUser = _createLocalFallbackUser(email: email);
      await _storage.saveUser(_currentUser!);
      await _storage.saveAutoLogin(rememberMe);
      _isOfflineMode = true;
      _error = null;
    } on ApiException catch (e) {
      _error = _mapApiError(e);
    } catch (e) {
      _error = 'unknown_error';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Sign up via Spring Boot REST API (Falls back to offline local user if server is unreachable)
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    DateTime? birthDate,
    String? gender,
    double? heightCm,
    double? weightKg,
    String? workoutGoal,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _authService.signUp(
        email: email,
        password: password,
        name: name,
        birthDate: birthDate,
        gender: gender,
        heightCm: heightCm,
        weightKg: weightKg,
        workoutGoal: workoutGoal,
      );

      _currentUser = user;
      await _storage.saveUser(user);
      await _storage.saveAutoLogin(true);
      _isOfflineMode = false;
      _error = null;
    } on NetworkException {
      // Spring Boot backend not running or unreachable -> Fallback to Offline Local Sign Up
      _currentUser = _createLocalFallbackUser(
        email: email,
        name: name,
        birthDate: birthDate,
        gender: gender,
        heightCm: heightCm,
        weightKg: weightKg,
        workoutGoal: workoutGoal,
      );
      await _storage.saveUser(_currentUser!);
      await _storage.saveAutoLogin(true);
      _isOfflineMode = true;
      _error = null;
    } on ApiException catch (e) {
      _error = _mapApiError(e);
    } catch (e) {
      _error = 'unknown_error';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// TEST ONLY: 백엔드 호출 없이 로컬 오프라인 유저로 즉시 로그인 처리한다.
  /// 디버그 빌드에서 로그인 화면 UI 확인용으로만 쓰고, 배포 전 제거할 것.
  void debugSkipLogin() {
    if (!kDebugMode) return;
    _currentUser =
        _createLocalFallbackUser(email: 'test@bpt.dev', name: 'Tester');
    _isOfflineMode = true;
    _error = null;
    notifyListeners();
  }

  UserModel _createLocalFallbackUser({
    required String email,
    String? name,
    DateTime? birthDate,
    String? gender,
    double? heightCm,
    double? weightKg,
    String? workoutGoal,
  }) {
    final effectiveName = (name != null && name.isNotEmpty)
        ? name
        : (email.contains('@') ? email.split('@')[0] : email);
    final initials =
        effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'U';

    return UserModel(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      username: email.trim(),
      name: effectiveName,
      email: email.trim(),
      password: '',
      avatarInitials: initials,
      birthDate: birthDate,
      gender: gender,
      heightCm: heightCm ?? 175,
      weightKg: weightKg ?? 70,
      workoutGoal: workoutGoal,
      joinedAt: DateTime.now(),
    );
  }

  /// Update profile data
  Future<void> updateProfile(UserModel updated) async {
    // 화면(예: 프로필 수정 바텀시트)이 서버 왕복을 기다리지 않고 바로 닫히고
    // 최신 값을 보여줄 수 있도록, 로컬 상태부터 즉시 반영한 뒤 저장/동기화는
    // 백그라운드에서 진행한다.
    _currentUser = updated;
    notifyListeners();
    await _storage.saveUser(updated);
    try {
      await _authService.saveUserData(updated);
    } catch (_) {
      // Saved locally if offline
    }
  }

  /// Logout
  Future<void> logout() async {
    await _storage.clearSession();
    _currentUser = null;
    _error = null;
    _isOfflineMode = false;
    notifyListeners();
  }

  /// 회원 탈퇴. 서버 탈퇴 API가 아직 없어 로컬 세션/저장 데이터만 정리한다.
  /// TODO: 실제 백엔드 탈퇴 엔드포인트가 생기면 여기서 호출을 추가할 것.
  Future<void> deleteAccount() async {
    await _storage.clearSession();
    _currentUser = null;
    _error = null;
    _isOfflineMode = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _mapApiError(ApiException exception) {
    if (exception is NetworkException) {
      return 'network_error';
    } else if (exception is UnauthorizedException) {
      return 'username_or_password_incorrect';
    } else if (exception.statusCode == 409) {
      return 'username_already_exists';
    }
    return 'unknown_error';
  }
}

final authNotifierProvider = ChangeNotifierProvider<AuthNotifier>((ref) {
  final authService = ref.watch(authServiceProvider);
  final storage = ref.watch(localStorageServiceProvider);
  return AuthNotifier(authService, storage);
});

final autoLoginProvider = StateProvider<bool>((ref) => false);
