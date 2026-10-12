import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../providers/account_recovery_provider.dart';
import '../widgets/auth_dark_form.dart';

class AccountRecoveryScreen extends ConsumerStatefulWidget {
  const AccountRecoveryScreen({super.key});

  @override
  ConsumerState<AccountRecoveryScreen> createState() =>
      _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends ConsumerState<AccountRecoveryScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  bool _resetMode = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  String? _passwordError;

  @override
  void dispose() {
    for (final controller in [
      _email,
      _code,
      _username,
      _password,
      _confirmation
    ]) {
      controller.dispose();
    }
    for (final focus in [
      _emailFocus,
      _codeFocus,
      _usernameFocus,
      _passwordFocus,
      _confirmationFocus
    ]) {
      focus.dispose();
    }
    super.dispose();
  }

  void _changeMode(bool reset) {
    FocusScope.of(context).unfocus();
    if (reset != _resetMode) {
      ref.read(accountRecoveryProvider.notifier).restartVerification();
      _code.clear();
    }
    setState(() {
      _resetMode = reset;
      _passwordError = null;
      _password.clear();
      _confirmation.clear();
    });
  }

  void _back({String? email}) {
    if (context.canPop()) {
      context.pop(email);
    } else {
      context.go(RouteConstants.login);
    }
  }

  Future<void> _sendCode() async {
    if (_resetMode && _username.text.trim().isEmpty) {
      _usernameFocus.requestFocus();
      showAppToast(context, '아이디를 입력해줘.', type: AppToastType.error);
      return;
    }
    final notifier = ref.read(accountRecoveryProvider.notifier);
    final sent =
        await notifier.sendCode(username: _resetMode ? _username.text : null);
    if (!mounted) return;
    if (sent) {
      _code.clear();
      // The code field only becomes enabled after this rebuild, so
      // requesting focus must wait for that frame or it's silently dropped.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
    } else {
      _emailFocus.requestFocus();
    }
  }

  Future<void> _verifyCode() async {
    final notifier = ref.read(accountRecoveryProvider.notifier);
    await notifier.verifyCode(_code.text);
    if (!mounted) return;
    if (ref.read(accountRecoveryProvider).verified) {
      FocusScope.of(context).unfocus();
      if (!_resetMode) await notifier.findUsername();
    }
  }

  Future<void> _resetPassword() async {
    final state = ref.read(accountRecoveryProvider);
    if (!state.verified || state.resetting) return;
    if (_username.text.trim().isEmpty) {
      _usernameFocus.requestFocus();
      showAppToast(context, '아이디를 입력해줘.', type: AppToastType.error);
      return;
    }
    setState(() {
      _passwordError = _password.text.length < 6
          ? '비밀번호를 6자 이상 입력해줘.'
          : _password.text != _confirmation.text
              ? '비밀번호가 서로 달라. 다시 확인해줘.'
              : null;
    });
    if (_passwordError != null) return;
    FocusScope.of(context).unfocus();
    final error = await ref
        .read(accountRecoveryProvider.notifier)
        .resetPassword(username: _username.text, newPassword: _password.text);
    if (!mounted) return;
    if (error != null) {
      // 아이디·이메일이 같은 계정이 아니면 USER_NOT_FOUND → 토스트로 알린다.
      showAppToast(context, error, type: AppToastType.error);
      return;
    }
    _password.clear();
    _confirmation.clear();
    showAppToast(context, '비밀번호를 바꿨어. 새 비밀번호로 로그인해줘.');
    _back();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountRecoveryProvider);
    return AuthScrollScaffold(
      title: '계정 찾기',
      onBack: _back,
      body: [
        _tabs(),
        const SizedBox(height: 24),
        Text(
          _resetMode ? '비밀번호 까먹었어?' : '아이디 까먹었어?',
          style: const TextStyle(
              fontSize: 27,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -1),
        ),
        const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Image.asset(
            state.sent || _resetMode
                ? 'assets/images/character/face2.png'
                : 'assets/images/character/face.png',
            width: 62,
            height: 68,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.purple,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomRight: Radius.circular(22),
                bottomLeft: Radius.circular(3),
              ),
            ),
            child: Text(
              state.verified ? '인증 완료! 이제 확인해봐!' : '이메일만 인증하면 바로 찾아줄게!',
              style: const TextStyle(
                  color: AppColors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
          )),
        ]),
        const SizedBox(height: 16),
        const Text('테스트 서버 · 인증번호는 메일 대신 서버 로그에 찍혀.',
            style: TextStyle(color: Color(0xFF999999), fontSize: 11)),
        const SizedBox(height: 12),
        // 비밀번호 재설정은 아이디·이메일이 같은 계정인지 먼저 맞춰본 뒤 인증번호를 보낸다.
        if (_resetMode) ...[
          const AuthFieldLabel('아이디'),
          AuthTextField(
            controller: _username,
            focus: _usernameFocus,
            hint: '아이디를 입력해줘',
            // visiblePassword: iOS에서 영문(ASCII) 키보드로 열린다.
            keyboard: TextInputType.visiblePassword,
            formatters: idInputFormatters,
            onChanged: (_) {
              ref.read(accountRecoveryProvider.notifier).restartVerification();
              _code.clear();
              _password.clear();
              _confirmation.clear();
              setState(() => _passwordError = null);
            },
          ),
          const SizedBox(height: 14),
        ],
        const AuthFieldLabel('이메일'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: AuthTextField(
            controller: _email,
            focus: _emailFocus,
            hint: '이메일을 입력해줘',
            // visiblePassword: iOS에서 영문(ASCII) 키보드로 열린다.
            keyboard: TextInputType.visiblePassword,
            formatters: englishOnlyFormatters,
            onChanged: (value) {
              ref.read(accountRecoveryProvider.notifier).changeEmail(value);
              _code.clear();
              _password.clear();
              _confirmation.clear();
              setState(() => _passwordError = null);
            },
          )),
          const SizedBox(width: 12),
          AuthStatusButton(
              label: state.sent
                  ? '전송 완료'
                  : state.sending
                      ? '보내는 중'
                      : '인증하기',
              complete: state.sent,
              onTap: state.sent || state.sending ? null : _sendCode),
        ]),
        const SizedBox(height: 14),
        const AuthFieldLabel('인증 코드'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: AuthTextField(
            controller: _code,
            focus: _codeFocus,
            hint: '인증 코드 6자리',
            enabled: state.sent && !state.verified,
            keyboard: TextInputType.number,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6)
            ],
            onChanged: (_) => setState(() {}),
          )),
          const SizedBox(width: 12),
          AuthStatusButton(
              label: state.verified
                  ? '인증 완료'
                  : state.verifying
                      ? '확인 중'
                      : '인증하기',
              complete: state.verified,
              onTap: state.sent &&
                      !state.verified &&
                      !state.verifying &&
                      _code.text.length == 6
                  ? _verifyCode
                  : null),
        ]),
        if (state.error != null) ...[
          const SizedBox(height: 10),
          Text(state.error!,
              style: const TextStyle(color: AppColors.red, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        if (!_resetMode && state.verified) _result(state),
        if (_resetMode && state.verified) ...[
          const AuthFieldLabel('새 비밀번호'),
          AuthTextField(
              controller: _password,
              focus: _passwordFocus,
              hint: '6자 이상 입력해줘',
              obscure: _hidePassword,
              suffix: authEyeToggle(_hidePassword,
                  () => setState(() => _hidePassword = !_hidePassword))),
          const SizedBox(height: 14),
          const AuthFieldLabel('새 비밀번호 확인'),
          AuthTextField(
              controller: _confirmation,
              focus: _confirmationFocus,
              hint: '비밀번호를 한 번 더 입력해줘',
              obscure: _hideConfirmation,
              suffix: authEyeToggle(
                  _hideConfirmation,
                  () =>
                      setState(() => _hideConfirmation = !_hideConfirmation))),
          if (_passwordError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_passwordError!,
                  style: const TextStyle(color: AppColors.red, fontSize: 13)),
            ),
        ],
      ],
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthPillButton(
            label: _resetMode ? '비밀번호 재설정하기' : '로그인하러 가기',
            onTap: !state.verified || state.resetting
                ? null
                : _resetMode
                    ? _resetPassword
                    // 찾은 아이디를 로그인 화면 아이디 칸에 채운다.
                    : () => _back(email: state.username),
            background: AppColors.white,
            foreground: AppColors.black,
            disabledBackground: AppColors.grey,
            disabledForeground: const Color(0xFF666666),
          ),
          const SizedBox(height: 10),
          AuthPillButton(
            label: _resetMode ? '아이디 찾기' : '비밀번호 재설정하기',
            onTap: () => _changeMode(!_resetMode),
            background: AppColors.grey,
            foreground: AppColors.white,
            borderColor: const Color(0xFF2B2B2B),
          ),
        ],
      ),
    );
  }

  Widget _tabs() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: AppColors.grey, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          for (final reset in [false, true])
            Expanded(
                child: TextButton(
              onPressed: () => _changeMode(reset),
              style: TextButton.styleFrom(
                backgroundColor:
                    _resetMode == reset ? AppColors.green : Colors.transparent,
                foregroundColor: _resetMode == reset
                    ? AppColors.black
                    : const Color(0xFF888888),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(reset ? '비밀번호 재설정' : '아이디 찾기',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            )),
        ]),
      );

  Widget _result(AccountRecoveryState state) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppColors.green, borderRadius: BorderRadius.circular(28)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('내 아이디',
              style: TextStyle(
                  color: Color(0xFF536E29),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(state.username ?? (state.finding ? '찾는 중…' : '-'),
              style: const TextStyle(
                  color: AppColors.black,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
        ]),
      );
}
