import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../models/user_model.dart';
import '../../../services/auth_service.dart';
import '../../../services/local_storage_service.dart';

/// Account identity plus login lifetime; token refresh does not invalidate it.
/// Keeping the notifier instance also invalidates leases on provider disposal.
class AuthSessionLease {
  AuthSessionLease._(this._owner, this.userId, this.generation);
  final AuthNotifier _owner;
  final String userId;
  final int generation;
  bool get isCurrent =>
      !_owner._disposed &&
      _owner._sessionGeneration == generation &&
      _owner.currentUser?.id == userId;
}

// ── Auth Notifier (Spring Boot REST API + Offline Dev Fallback) ──────────────
class AuthNotifier extends ChangeNotifier {
  final AuthService _authService;
  final LocalStorageService _storage;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _isOfflineMode = false;
  // Unique across notifier/provider recreation as well as relogin.
  static int _nextSessionGeneration = 0;
  int _sessionGeneration = ++_nextSessionGeneration;
  int _advanceSession() => _sessionGeneration = ++_nextSessionGeneration;
  bool _disposed = false;
  static const _sessionChangedMessage = '로그인 상태가 바뀌었어. 다시 확인해 줘.';

  // Keep an already-started clear/save in order with a subsequent login. This
  // prevents delayed persistence from clearing the new account's credentials.
  Future<void> _persist(Future<void> Function() action) =>
      _storage.serializeSessionWrite(action);

  Future<void> _saveUser(UserModel user, AuthSessionLease lease) =>
      _persist(() async {
        if (lease.isCurrent) await _storage.saveUser(user);
      });

  Future<void> _saveLogin(UserModel user, bool rememberMe) {
    final lease = captureSession()!;
    final access = _authService.authToken, refresh = _authService.refreshToken;
    return _persist(() async {
      if (!lease.isCurrent) return;
      await _storage.saveUser(user);
      await _storage.saveAuthToken(access);
      await _storage.saveRefreshToken(refresh);
      await _storage.saveAutoLogin(rememberMe);
    });
  }

  AuthNotifier(this._authService, this._storage) {
    // 액세스 토큰은 1시간이면 만료된다. API 클라이언트가 자동으로 갱신하면
    // 새 토큰을 기기에 저장하고, 리프레시 토큰까지 만료되면 로그인 화면으로 보낸다.
    _authService.onTokensRefreshed = (accessToken, refreshToken) {
      final lease = captureSession();
      if (lease == null) return;
      unawaited(_persist(() async {
        if (!lease.isCurrent) return;
        await _storage.saveAuthToken(accessToken);
        await _storage.saveRefreshToken(refreshToken);
      }));
    };
    _authService.onSessionExpired = () {
      if (!_disposed && _currentUser != null) unawaited(logout());
    };
  }

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isOfflineMode => _isOfflineMode;
  ({String userId, int generation})? get sessionIdentity => _currentUser == null
      ? null
      : (userId: _currentUser!.id, generation: _sessionGeneration);
  AuthSessionLease? captureSession() => _currentUser == null || _disposed
      ? null
      : AuthSessionLease._(this, _currentUser!.id, _sessionGeneration);

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
    _advanceSession();
    _authService.restoreAuthToken(token,
        refreshToken: _storage.loadRefreshToken());

    _currentUser = cachedUser;
    final lease = captureSession()!;
    notifyListeners();

    // Try background refresh from Spring Boot server
    try {
      final freshUser = await _authService.fetchUserProfile(
          sessionGuard: () => lease.isCurrent);
      if (!lease.isCurrent) return false;
      if (freshUser.id != lease.userId) {
        await logout();
        return false;
      }
      // 서버에 주간 목표가 아직 없으면 기기에 있던 값을 유지한다.
      _currentUser = freshUser.copyWith(
          weeklyFrequency:
              freshUser.weeklyFrequency ?? cachedUser.weeklyFrequency);
      await _saveUser(_currentUser!, lease);
      if (!lease.isCurrent) return false;
      _isOfflineMode = false;
      notifyListeners();
    } on UnauthorizedException {
      if (!lease.isCurrent) return false;
      // 토큰이 만료됐거나 서버에서 거절됨 → 저장된 세션을 지우고 로그인 화면으로
      await logout();
      return false;
    } catch (_) {
      if (!lease.isCurrent) return false;
      // Offline fallback: continue with cached user profile
      _isOfflineMode = true;
    }

    return true;
  }

  /// Login via Spring Boot REST API.
  /// 서버에 연결되지 않으면 비밀번호를 확인할 수 없으니 로그인하지 않고
  /// 'network_error' 를 남긴다. (저장된 토큰으로 되살리는 자동 로그인은 [tryAutoLogin])
  Future<void> login(
    String email,
    String password, {
    bool rememberMe = false,
  }) async {
    final generation = _advanceSession();
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _authService.login(
          email: email,
          password: password,
          canCommit: () => !_disposed && generation == _sessionGeneration);
      if (_disposed || generation != _sessionGeneration) return;
      _currentUser = user;
      await _saveLogin(user, rememberMe);
      if (_disposed || generation != _sessionGeneration) return;
      _isOfflineMode = false;
      _error = null;
    } on ApiException catch (e) {
      if (_disposed || generation != _sessionGeneration) return;
      _error = _mapApiError(e);
    } catch (e) {
      if (_disposed || generation != _sessionGeneration) return;
      _error = 'unknown_error';
    }

    if (_disposed || generation != _sessionGeneration) return;
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
    final generation = _advanceSession();
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
        canCommit: () => !_disposed && generation == _sessionGeneration,
      );
      if (_disposed || generation != _sessionGeneration) {
        return _sessionChangedMessage;
      }
      _currentUser = user;
      await _saveLogin(user, true);
      if (_disposed || generation != _sessionGeneration) {
        return _sessionChangedMessage;
      }
      _isOfflineMode = false;
    } on NetworkException {
      if (_disposed || generation != _sessionGeneration) {
        return _sessionChangedMessage;
      }
      message = '서버에 연결할 수 없어. 인터넷 연결을 확인하고 다시 시도해줘.';
    } on ApiException catch (e) {
      if (_disposed || generation != _sessionGeneration) {
        return _sessionChangedMessage;
      }
      // 백엔드가 보내는 안내 문구(예: 이미 가입된 이메일 주소입니다.)를 그대로 보여준다.
      message = e.message;
    } catch (_) {
      if (_disposed || generation != _sessionGeneration) {
        return _sessionChangedMessage;
      }
      message = '가입 중에 문제가 생겼어. 잠시 후 다시 시도해줘.';
    }

    if (_disposed || generation != _sessionGeneration) {
      return _sessionChangedMessage;
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
    final lease = captureSession();
    if (lease == null) return null;
    if (user != null) {
      _currentUser = user.copyWith(
        gender: gender,
        heightCm: heightCm,
        weightKg: weightKg,
        workoutGoal: workoutGoal,
        weeklyFrequency: weeklyFrequency,
      );
      await _saveUser(_currentUser!, lease);
      if (!lease.isCurrent) return null;
      notifyListeners();
    }
    try {
      await _authService.updateOnboarding(
        sessionGuard: () => lease.isCurrent,
        gender: gender,
        heightCm: heightCm,
        weightKg: weightKg,
        workoutGoal: workoutGoal,
        weeklyFrequency: weeklyFrequency,
      );
      return null;
    } on ApiException catch (e) {
      if (!lease.isCurrent) return null;
      return e is NetworkException
          ? '서버에 연결할 수 없어서 신체 정보를 저장하지 못했어.'
          : e.message;
    }
  }

  /// TEST ONLY: 백엔드 호출 없이 로컬 오프라인 유저로 즉시 로그인 처리한다.
  /// 디버그 빌드에서 로그인 화면 UI 확인용으로만 쓰고, 배포 전 제거할 것.
  void debugSkipLogin() {
    if (!kDebugMode) return;
    _advanceSession();
    _authService.restoreAuthToken(null);
    unawaited(_persist(_storage.clearSession));
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
      email:
          (email.isEmpty && username.contains('@') ? username : email).trim(),
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
    if (_currentUser?.id != updated.id) return;
    final lease = captureSession()!;
    // 화면(예: 프로필 수정 바텀시트)이 서버 왕복을 기다리지 않고 바로 닫히고
    // 최신 값을 보여줄 수 있도록, 로컬 상태부터 즉시 반영한 뒤 저장/동기화는
    // 백그라운드에서 진행한다.
    _currentUser = updated;
    notifyListeners();
    await _saveUser(updated, lease);
    if (!lease.isCurrent) return;
    try {
      await _authService.saveUserData(updated,
          sessionGuard: () => lease.isCurrent);
    } catch (_) {
      // Saved locally if offline
    }
  }

  /// Logout
  Future<void> logout() async {
    // Invalidate synchronously, before persistence/network callbacks can resume.
    _advanceSession();
    _authService.restoreAuthToken(null);
    _currentUser = null;
    _error = null;
    _isOfflineMode = false;
    _isLoading = false;
    notifyListeners();
    await _persist(_storage.clearSession);
  }

  /// 체형 촬영 완료를 서버에 기록하고, 오늘 날짜를 마지막 측정일로 반영한다.
  /// 서버에 못 보내도 기기에는 측정일을 남겨 재측정 알림이 바로 사라지게 한다.
  Future<void> recordBodyScan({String? sessionPath}) async {
    final user = _currentUser;
    final lease = captureSession();
    if (user == null || lease == null) return;
    try {
      final fresh = await _authService.recordBodyScan(
          sessionPath: sessionPath, sessionGuard: () => lease.isCurrent);
      if (!lease.isCurrent) return;
      if (fresh.id != lease.userId) {
        await logout();
        return;
      }
      _currentUser = fresh.copyWith(
          weeklyFrequency: fresh.weeklyFrequency ?? user.weeklyFrequency);
    } catch (_) {
      if (!lease.isCurrent) return;
      _currentUser = _currentUser!.copyWith(lastBodyScanDate: DateTime.now());
    }
    await _saveUser(_currentUser!, lease);
    if (!lease.isCurrent) return;
    notifyListeners();
  }

  /// 회원 탈퇴. 서버가 계정을 지운 것을 확인한 뒤에만 로그아웃하고, 그 계정의
  /// 프로필·운동 기록 캐시·전송 대기열을 기기에서 지운다.
  /// 성공하면 null, 실패하면 화면에 보여줄 안내 문구를 돌려준다 (로그인 상태 유지).
  Future<String?> deleteAccount() async {
    final user = _currentUser;
    final lease = captureSession();
    if (lease == null) return null;
    try {
      await _authService.deleteAccount(sessionGuard: () => lease.isCurrent);
    } on NetworkException {
      if (!lease.isCurrent) return _sessionChangedMessage;
      return '서버에 연결할 수 없어서 탈퇴하지 못했어. 인터넷 연결을 확인하고 다시 시도해줘.';
    } catch (_) {
      if (!lease.isCurrent) return _sessionChangedMessage;
      return '탈퇴하지 못했어. 잠시 후 다시 시도해줘.';
    }
    if (!lease.isCurrent) return _sessionChangedMessage;
    // Invalidate account-bound requests before removing their persisted queues.
    _advanceSession();
    _authService.restoreAuthToken(null);
    _currentUser = null;
    _error = null;
    _isOfflineMode = false;
    notifyListeners();
    await _persist(() async {
      if (user != null) await _storage.removeWorkoutData(user.id);
      await _storage.removeUser();
      await _storage.clearSession();
    });
    return null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _advanceSession();
    super.dispose();
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

/// 지금 로그인한 사용자 ID (로그인 안 했으면 null). 운동 기록 캐시와 전송
/// 대기열을 계정별로 나누는 데 쓴다. 바뀌면 그 Provider들이 새로 만들어진다.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authNotifierProvider.select((a) => a.currentUser?.id)),
);

final authSessionIdentityProvider =
    Provider<({String userId, int generation})?>(
  (ref) => ref.watch(authNotifierProvider.select((a) => a.sessionIdentity)),
);

final autoLoginProvider = StateProvider<bool>((ref) => false);
