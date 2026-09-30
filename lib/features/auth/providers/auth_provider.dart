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

    // 저장해 둔 토큰이 없으면 서버 인증을 되살릴 수 없으니 다시 로그인하게 한다.
    final token = _storage.loadAuthToken();
    if (token == null) return false;
    _authService.restoreAuthToken(token);

    _currentUser = cachedUser;
    notifyListeners();

    // Try background refresh from Spring Boot server
    try {
      final freshUser = await _authService.fetchUserProfile();
      _currentUser = freshUser;
      await _storage.saveUser(freshUser);
      _isOfflineMode = false;
      notifyListeners();
    } on UnauthorizedException {
      // 토큰이 만료됐거나 서버에서 거절됨 → 저장된 세션을 지우고 로그인 화면으로
      await logout();
      return false;
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
      await _storage.saveAuthToken(_authService.authToken);
      await _storage.saveAutoLogin(rememberMe);
      _isOfflineMode = false;
      _error = null;
    } on NetworkException {
      // Spring Boot backend not running or unreachable -> Fallback to Offline Local Login
      _currentUser = _createLocalFallbackUser(username: email);
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

  /// 서버에 계정을 만들고 바로 로그인 상태로 둔다.
  /// 성공하면 null, 실패하면 화면에 보여줄 안내 문구를 돌려준다.
  /// 서버에 연결되지 않으면 계정이 만들어지지 않으므로 오프라인 가입은 하지 않는다.
  Future<String?> signUp({
    required String username,
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
    required DateTime birthDate,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    String? message;
    try {
      final user = await _authService.signUp(
        username: username,
        email: email,
        password: password,
        name: name,
        phoneNumber: phoneNumber,
        birthDate: '${birthDate.year.toString().padLeft(4, '0')}-'
            '${birthDate.month.toString().padLeft(2, '0')}-'
            '${birthDate.day.toString().padLeft(2, '0')}',
      );
      _currentUser = user;
      await _storage.saveUser(user);
      await _storage.saveAuthToken(_authService.authToken);
      await _storage.saveAutoLogin(true);
      _isOfflineMode = false;
    } on NetworkException {
      message = '서버에 연결할 수 없어. 인터넷 연결을 확인하고 다시 시도해줘.';
    } on ApiException catch (e) {
      // 백엔드가 보내는 안내 문구(예: 이미 가입된 이메일 주소입니다.)를 그대로 보여준다.
      message = e.message;
    } catch (_) {
      message = '가입 중에 문제가 생겼어. 잠시 후 다시 시도해줘.';
    }

    _error = message;
    _isLoading = false;
    notifyListeners();
    return message;
  }

  /// 온보딩 정보를 서버에 저장하고 현재 사용자 정보에도 반영한다.
  /// 실패해도 온보딩 진행은 막지 않고, 안내 문구만 돌려준다.
  Future<String?> saveOnboarding({
    required String gender,
    required double heightCm,
    required double weightKg,
    required String workoutGoal,
    required int weeklyFrequency,
  }) async {
    final user = _currentUser;
    if (user != null) {
      _currentUser = user.copyWith(
        gender: gender,
        heightCm: heightCm,
        weightKg: weightKg,
        workoutGoal: workoutGoal,
      );
      await _storage.saveUser(_currentUser!);
      notifyListeners();
    }
    try {
      await _authService.updateOnboarding(
        gender: gender,
        heightCm: heightCm,
        weightKg: weightKg,
        workoutGoal: workoutGoal,
        weeklyFrequency: weeklyFrequency,
      );
      return null;
    } on ApiException catch (e) {
      return e is NetworkException
          ? '서버에 연결할 수 없어서 신체 정보를 저장하지 못했어.'
          : e.message;
    }
  }

  /// TEST ONLY: 백엔드 호출 없이 로컬 오프라인 유저로 즉시 로그인 처리한다.
  /// 디버그 빌드에서 로그인 화면 UI 확인용으로만 쓰고, 배포 전 제거할 것.
  void debugSkipLogin() {
    if (!kDebugMode) return;
    _currentUser = _createLocalFallbackUser(
        username: 'tester', email: 'test@bpt.dev', name: 'Tester');
    _isOfflineMode = true;
    _error = null;
    notifyListeners();
  }

  /// 서버 없이 쓰는 로컬 사용자. [username]은 아이디이며, 이메일이 들어오면
  /// @ 앞부분을 아이디로 쓴다.
  UserModel _createLocalFallbackUser({
    required String username,
    String email = '',
    String? name,
    DateTime? birthDate,
    String? gender,
    double? heightCm,
    double? weightKg,
    String? workoutGoal,
  }) {
    final id = username.contains('@') ? username.split('@')[0] : username;
    final effectiveName = (name != null && name.isNotEmpty) ? name : id;
    final initials =
        effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'U';

    return UserModel(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      username: id.trim(),
      name: effectiveName,
      email: (email.isEmpty && username.contains('@') ? username : email).trim(),
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
    _authService.restoreAuthToken(null);
    _currentUser = null;
    _error = null;
    _isOfflineMode = false;
    notifyListeners();
  }

  /// 회원 탈퇴. 서버 탈퇴 API가 아직 없어 로컬 세션/저장 데이터만 정리한다.
  /// TODO: 실제 백엔드 탈퇴 엔드포인트가 생기면 여기서 호출을 추가할 것.
  Future<void> deleteAccount() async {
    await _storage.clearSession();
    _authService.restoreAuthToken(null);
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
