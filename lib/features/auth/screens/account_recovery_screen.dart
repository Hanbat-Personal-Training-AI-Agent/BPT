import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
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
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  bool _resetMode = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  String? _passwordError;

  @override
  void dispose() {
    for (final controller in [_email, _code, _password, _confirmation]) {
      controller.dispose();
    }
    for (final focus in [
      _emailFocus,
      _codeFocus,
      _passwordFocus,
      _confirmationFocus
    ]) {
      focus.dispose();
    }
    super.dispose();
  }

  void _changeMode(bool reset) {
    FocusScope.of(context).unfocus();
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
    final notifier = ref.read(accountRecoveryProvider.notifier);
    final sent = await notifier.sendCode();
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
    await ref.read(accountRecoveryProvider.notifier).verifyCode(_code.text);
    if (!mounted) return;
    if (ref.read(accountRecoveryProvider).verified) {
      FocusScope.of(context).unfocus();
    }
  }

  void _previewReset() {
    if (!ref.read(accountRecoveryProvider).verified) return;
    setState(() {
      _passwordError = _password.text.length < 6
          ? '비밀번호를 6자 이상 입력해줘.'
          : _password.text != _confirmation.text
              ? '비밀번호가 서로 달라. 다시 확인해줘.'
              : null;
    });
    if (_passwordError != null) return;
    FocusScope.of(context).unfocus();
    _password.clear();
    _confirmation.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('비밀번호 재설정은 아직 서버에서 지원하지 않아. 실제로 바뀌지 않았어.'),
    ));
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
            label: _resetMode ? '비밀번호 재설정하기' : '이 아이디로 로그인',
            onTap: !state.verified
                ? null
                : _resetMode
                    ? _previewReset
                    : () => _back(email: state.email),
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
          const Text('인증된 로그인 이메일',
              style: TextStyle(
                  color: Color(0xFF536E29),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(state.email,
              style: const TextStyle(
                  color: AppColors.black,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('아이디 대신 이 이메일로 로그인할 수 있어.',
              style: TextStyle(color: Color(0xFF536E29), fontSize: 12)),
        ]),
      );
}
