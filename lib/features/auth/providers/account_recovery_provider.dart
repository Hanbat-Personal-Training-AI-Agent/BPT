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
    this.error,
  });

  final String email;
  final bool sending;
  final bool sent;
  final bool verifying;
  final bool verified;
  final String? error;

  AccountRecoveryState copyWith({
    bool? sending,
    bool? sent,
    bool? verifying,
    bool? verified,
    String? error,
  }) =>
      AccountRecoveryState(
        email: email,
        sending: sending ?? this.sending,
        sent: sent ?? this.sent,
        verifying: verifying ?? this.verifying,
        verified: verified ?? this.verified,
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

  /// 서버에 인증번호 발송을 요청한다. 성공하면 true.
  Future<bool> sendCode() async {
    if (state.sending) return false;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(state.email)) {
      state = state.copyWith(error: '올바른 이메일을 입력해줘.');
      return false;
    }
    final email = state.email;
    state = state.copyWith(sending: true);
    String? error;
    try {
      await _authService.requestEmailVerification(email);
    } on ApiException catch (e) {
      error = _message(e);
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
    String? error;
    try {
      verified = await _authService.confirmEmailVerification(
          email: email, code: code);
      if (!verified) error = '인증 코드가 맞지 않아. 다시 확인해줘.';
    } on ApiException catch (e) {
      error = _message(e);
    }
    if (!mounted || state.email != email) return;
    state = state.copyWith(verifying: false, verified: verified, error: error);
  }

  String _message(ApiException e) => e is NetworkException
      ? '서버에 연결할 수 없어. 인터넷 연결을 확인하고 다시 시도해줘.'
      : e.message;
}

final accountRecoveryProvider = StateNotifierProvider.autoDispose<
    AccountRecoveryNotifier, AccountRecoveryState>(
  (ref) => AccountRecoveryNotifier(ref.watch(authServiceProvider)),
);
