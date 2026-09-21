import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/sign_up_provider.dart';
import '../widgets/auth_dark_form.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _id = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _phone = TextEditingController();
  final _birthDate = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _idFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _birthDateFocus = FocusNode(canRequestFocus: false);

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  bool _nameTouched = false;
  bool _emailTouched = false;
  bool _idTouched = false;
  bool _passwordTouched = false;
  bool _confirmPasswordTouched = false;
  bool _phoneTouched = false;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onNameFocusChange);
    _emailFocus.addListener(_onEmailFocusChange);
    _idFocus.addListener(_onIdFocusChange);
    _passwordFocus.addListener(_onPasswordFocusChange);
    _confirmPasswordFocus.addListener(_onConfirmPasswordFocusChange);
    _phoneFocus.addListener(_onPhoneFocusChange);
  }

  void _onNameFocusChange() {
    if (!_nameFocus.hasFocus) setState(() => _nameTouched = true);
  }

  void _onIdFocusChange() {
    if (!_idFocus.hasFocus) setState(() => _idTouched = true);
  }

  void _onEmailFocusChange() {
    if (!_emailFocus.hasFocus) setState(() => _emailTouched = true);
  }

  void _onPasswordFocusChange() {
    if (!_passwordFocus.hasFocus) setState(() => _passwordTouched = true);
  }

  void _onConfirmPasswordFocusChange() {
    if (!_confirmPasswordFocus.hasFocus) {
      setState(() => _confirmPasswordTouched = true);
    }
  }

  void _onPhoneFocusChange() {
    if (!_phoneFocus.hasFocus) setState(() => _phoneTouched = true);
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onNameFocusChange);
    _emailFocus.removeListener(_onEmailFocusChange);
    _idFocus.removeListener(_onIdFocusChange);
    _passwordFocus.removeListener(_onPasswordFocusChange);
    _confirmPasswordFocus.removeListener(_onConfirmPasswordFocusChange);
    _phoneFocus.removeListener(_onPhoneFocusChange);
    for (final controller in [
      _name,
      _email,
      _id,
      _password,
      _confirmPassword,
      _phone,
      _birthDate,
    ]) {
      controller.dispose();
    }
    for (final focus in [
      _nameFocus,
      _emailFocus,
      _idFocus,
      _passwordFocus,
      _confirmPasswordFocus,
      _phoneFocus,
      _birthDateFocus,
    ]) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final state = ref.read(signUpProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: state.birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
      locale: const Locale('ko'),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Pretendard'),
          colorScheme: const ColorScheme.dark(
            primary: AppColors.green,
            onPrimary: AppColors.black,
            surface: AppColors.grey,
            onSurface: AppColors.white,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: AppColors.grey),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.green),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    ref.read(signUpProvider.notifier).setBirthDate(picked);
    _birthDate.text =
        '${picked.year}. ${picked.month.toString().padLeft(2, '0')}. '
        '${picked.day.toString().padLeft(2, '0')}';
  }

  void _submit(SignUpState state) {
    if (!state.canSubmit) return;
    FocusScope.of(context).unfocus();
    context.push(RouteConstants.onboardingGender);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signUpProvider);
    final notifier = ref.read(signUpProvider.notifier);
    return AuthScrollScaffold(
      title: '회원가입',
      onBack: () => context.pop(),
      body: [
        const SizedBox(height: 8),
        const AuthFieldLabel('이름'),
        AuthTextField(
          controller: _name,
          focus: _nameFocus,
          hint: '이름을 입력해줘',
          onChanged: notifier.changeName,
        ),
        if (_nameTouched && state.name.isNotEmpty && !state.nameValid) ...[
          const SizedBox(height: 8),
          const Text('이름은 두 글자 이상 입력해줘.',
              style: TextStyle(color: AppColors.red, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        const AuthFieldLabel('이메일'),
        AuthTextField(
          controller: _email,
          focus: _emailFocus,
          hint: '이메일을 입력해줘',
          keyboard: TextInputType.emailAddress,
          onChanged: notifier.changeEmail,
        ),
        if (_emailTouched && state.email.isNotEmpty && !state.emailValid) ...[
          const SizedBox(height: 8),
          const Text('올바른 이메일 형식이 아니야.',
              style: TextStyle(color: AppColors.red, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        const AuthFieldLabel('아이디'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: AuthTextField(
            controller: _id,
            focus: _idFocus,
            hint: '아이디를 입력해줘',
            onChanged: notifier.changeId,
          )),
          const SizedBox(width: 12),
          AuthStatusButton(
              label:
                  state.idCheck == IdCheckStatus.available ? '확인 완료' : '중복확인',
              complete: state.idCheck == IdCheckStatus.available,
              onTap: state.id.trim().isEmpty ||
                      state.idCheck == IdCheckStatus.available
                  ? null
                  : notifier.checkIdDuplicate),
        ]),
        if (state.idCheck == IdCheckStatus.taken) ...[
          const SizedBox(height: 8),
          const Text('이미 사용 중인 아이디예요. 다른 아이디를 입력해줘.',
              style: TextStyle(color: AppColors.red, fontSize: 13)),
        ] else if (_idTouched &&
            state.id.trim().isNotEmpty &&
            state.idCheck == IdCheckStatus.none) ...[
          const SizedBox(height: 8),
          const Text('아이디 중복확인을 해줘.',
              style: TextStyle(color: AppColors.red, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        const AuthFieldLabel('비밀번호'),
        AuthTextField(
          controller: _password,
          focus: _passwordFocus,
          hint: '영문, 숫자 포함 8자 이상',
          obscure: _hidePassword,
          onChanged: notifier.changePassword,
          suffix: authEyeToggle(_hidePassword,
              () => setState(() => _hidePassword = !_hidePassword)),
        ),
        if (_passwordTouched &&
            state.password.isNotEmpty &&
            !state.passwordValid) ...[
          const SizedBox(height: 8),
          const Text('영문, 숫자를 포함해 8자 이상이어야 해.',
              style: TextStyle(color: AppColors.red, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        const AuthFieldLabel('비밀번호 재확인'),
        AuthTextField(
          controller: _confirmPassword,
          focus: _confirmPasswordFocus,
          hint: '비밀번호를 한 번 더 입력해줘',
          obscure: _hideConfirmPassword,
          onChanged: notifier.changeConfirmPassword,
          suffix: state.confirmValid
              ? const Icon(Icons.check_rounded,
                  color: AppColors.green, size: 22)
              : authEyeToggle(
                  _hideConfirmPassword,
                  () => setState(
                      () => _hideConfirmPassword = !_hideConfirmPassword)),
        ),
        if (_confirmPasswordTouched &&
            state.confirmPassword.isNotEmpty &&
            !state.confirmValid) ...[
          const SizedBox(height: 8),
          const Text('비밀번호가 서로 달라. 다시 확인해줘.',
              style: TextStyle(color: AppColors.red, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        const AuthFieldLabel('전화번호'),
        AuthTextField(
          controller: _phone,
          focus: _phoneFocus,
          hint: '010-0000-0000',
          keyboard: TextInputType.phone,
          formatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
            _PhoneNumberFormatter(),
          ],
          onChanged: notifier.changePhone,
        ),
        if (_phoneTouched && state.phone.isNotEmpty && !state.phoneValid) ...[
          const SizedBox(height: 8),
          const Text('전화번호를 정확히 입력해줘.',
              style: TextStyle(color: AppColors.red, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        const AuthFieldLabel('생년월일'),
        AuthTextField(
          controller: _birthDate,
          focus: _birthDateFocus,
          hint: '2000. 01. 01',
          readOnly: true,
          onTap: _pickBirthDate,
          suffix: const Icon(Icons.calendar_today_outlined,
              color: Color(0xFF888888), size: 20),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: notifier.toggleAgreed,
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: state.agreed ? AppColors.green : Colors.transparent,
                border: Border.all(
                    color: state.agreed
                        ? AppColors.green
                        : const Color(0xFF444444)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: state.agreed
                  ? const Icon(Icons.check_rounded,
                      color: AppColors.black, size: 16)
                  : null,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('이용약관 및 개인정보 처리방침에 동의',
                  style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
            ),
          ]),
        ),
      ],
      bottomBar: AuthPillButton(
        label: '가입하기',
        onTap: state.canSubmit ? () => _submit(state) : null,
        background: AppColors.green,
        foreground: AppColors.black,
        disabledBackground: AppColors.green.withValues(alpha: 0.5),
        disabledForeground: AppColors.black.withValues(alpha: 0.5),
      ),
    );
  }
}

/// Formats digits as 010-1234-5678 while typing.
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 3 || i == 7) buffer.write('-');
      buffer.write(digits[i]);
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
