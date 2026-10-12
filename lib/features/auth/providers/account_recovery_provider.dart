import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../services/auth_service.dart';

class AccountRecoveryState {
  const AccountRecoveryState({
    this.email = '',
    this.sending = false,
    this.sent = false,
    this.verifying = false,
    this.verified = false,
    this.verificationToken,
    this.resetting = false,
    this.finding = false,
    this.username,
    this.error,
  });

  final String email;
  final bool sending;
  final bool sent;
  final bool verifying;
  final bool verified;

  /// 인증 확인 응답의 일회용 토큰. 아이디 찾기·비밀번호 재설정 중 한 번만 쓸 수 있다.
  final String? verificationToken;
  final bool resetting;
  final bool finding;

  /// 아이디 찾기로 받은 가입 아이디.
  final String? username;
  final String? error;

  AccountRecoveryState copyWith({
    bool? sending,
    bool? sent,
    bool? verifying,
    bool? verified,
    String? verificationToken,
    bool? resetting,
    bool? finding,
    String? username,
    bool clearToken = false,
    String? error,
  }) =>
      AccountRecoveryState(
        email: email,
        sending: sending ?? this.sending,
        sent: sent ?? this.sent,
        verifying: verifying ?? this.verifying,
        verified: verified ?? this.verified,
        verificationToken:
            clearToken ? null : verificationToken ?? this.verificationToken,
        resetting: resetting ?? this.resetting,
        finding: finding ?? this.finding,
        username: username ?? this.username,
        error: error,
      );
}

class AccountRecoveryNotifier extends StateNotifier<AccountRecoveryState> {
  AccountRecoveryNotifier(this._authService)
      : super(const AccountRecoveryState());

  final AuthService _authService;

  void changeEmail(String email) {
    if (email.trim() == state.email) return;
    // Editing the address invalidates the old code and recovered account.
    state = AccountRecoveryState(email: email.trim());
  }

  /// 이메일은 두고 인증을 처음부터 다시 받게 한다.
  /// 탭을 바꾸거나 비밀번호 재설정 아이디를 바꾸면 이전 인증은 쓸 수 없다
  /// (재설정은 아이디 확인을 거쳐 보낸 인증번호여야 하고, 토큰도 한 번만 쓸 수 있다).
  void restartVerification() {
    if (!state.sent && state.error == null) return;
    state = AccountRecoveryState(email: state.email);
  }

  /// 서버에 인증번호 발송을 요청한다. 성공하면 true.
  /// [username]을 주면 아이디·이메일이 같은 계정일 때만 보낸다.
  Future<bool> sendCode({String? username}) async {
    if (state.sending) return false;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(state.email)) {
      state = state.copyWith(error: '올바른 이메일을 입력해줘.');
      return false;
    }
    final email = state.email;
    state = state.copyWith(sending: true);
    String? error;
    try {
      await _authService.requestEmailVerification(email, username: username);
    } on ApiException catch (e) {
      error = e.code == 'USER_NOT_FOUND'
          ? '아이디와 이메일이 맞지 않아. 다시 확인해줘.'
          : _message(e);
    }
    // 요청하는 사이에 이메일을 바꿨으면 결과를 버린다.
    if (!mounted || state.email != email) return false;
    state = state.copyWith(sending: false, sent: error == null, error: error);
    return error == null;
  }

  Future<void> verifyCode(String code) async {
    if (!state.sent || state.verified || state.verifying) return;
    final email = state.email;
    state = state.copyWith(verifying: true);
    bool verified = false;
    String? token;
    String? error;
    try {
      final result = await _authService.confirmEmailVerification(
          email: email, code: code);
      verified = result.verified;
      token = result.token;
      if (!verified) error = '인증 코드가 맞지 않아. 다시 확인해줘.';
    } on ApiException catch (e) {
      error = _message(e);
    }
    if (!mounted || state.email != email) return;
    state = state.copyWith(
        verifying: false,
        verified: verified,
        verificationToken: token,
        error: error);
  }

  /// 인증 토큰으로 가입 아이디를 찾는다. 토큰은 여기서 쓰이고 사라진다.
  Future<void> findUsername() async {
    final token = state.verificationToken;
    if (!state.verified || state.finding || token == null) return;
    final email = state.email;
    state = state.copyWith(finding: true, error: state.error);
    String? username;
    String? error;
    // 서버에 닿았으면 결과와 상관없이 토큰은 이미 폐기됐다.
    var tokenUsed = true;
    try {
      username = await _authService.findUsername(verificationToken: token);
      if (username == null) error = '아이디를 찾지 못했어. 다시 시도해줘.';
    } on ApiException catch (e) {
      tokenUsed = e is! NetworkException;
      error = e.code == 'USER_NOT_FOUND'
          ? '이 이메일로 가입한 아이디가 없어.'
          : _message(e);
    }
    if (!mounted || state.email != email) return;
    state = state.copyWith(
        finding: false,
        username: username,
        clearToken: tokenUsed,
        error: error);
  }

  /// 인증된 이메일 + [username]으로 비밀번호를 바꾼다.
  /// 실패하면 화면에 띄울 문구를, 성공하면 null을 돌려준다.
  Future<String?> resetPassword({
    required String username,
    required String newPassword,
  }) async {
    if (!state.verified || state.resetting) return null;
    state = state.copyWith(resetting: true, error: state.error);
    String? error;
    try {
      await _authService.resetPassword(
        username: username,
        email: state.email,
        newPassword: newPassword,
        verificationToken: state.verificationToken,
      );
    } on ApiException catch (e) {
      error = e.code == 'USER_NOT_FOUND'
          ? '아이디와 이메일이 맞지 않아. 다시 확인해줘.'
          : _message(e);
    }
    if (mounted) state = state.copyWith(resetting: false, error: state.error);
    return error;
  }

  String _message(ApiException e) => e is NetworkException
      ? '서버에 연결할 수 없어. 인터넷 연결을 확인하고 다시 시도해줘.'
      : e.message;
}

final accountRecoveryProvider = StateNotifierProvider.autoDispose<
    AccountRecoveryNotifier, AccountRecoveryState>(
  (ref) => AccountRecoveryNotifier(ref.watch(authServiceProvider)),
);
