import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/home/providers/home_provider.dart';

/// 내정보 히어로 카드에서 진입하는 신상 정보 수정 화면.
///
/// 회원가입 화면과 같은 항목(이름·아이디·이메일·생년월일)을 다루지만, 이
/// 앱의 새 다크 카드 디자인 시스템(홈/프로필과 동일한 톤)으로 따로 만들었다
/// — 회원가입 화면의 외곽선 입력창 스타일을 그대로 가져오지 않는다.
/// 아이디·이메일은 계정 식별자라 여기서 바꿀 수 없고, 잠금 표시만 된다.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  DateTime? _birthDate;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  // 비밀번호는 선택 입력 — 비워두면 기존 비밀번호를 그대로 유지한다.
  bool get _passwordValid =>
      _passwordCtrl.text.isEmpty ||
      (_passwordCtrl.text.length >= 8 &&
          RegExp(r'[A-Za-z]').hasMatch(_passwordCtrl.text) &&
          RegExp(r'\d').hasMatch(_passwordCtrl.text));
  bool get _confirmValid =>
      _passwordCtrl.text.isEmpty ||
      _confirmPasswordCtrl.text == _passwordCtrl.text;
  bool get _canSave => _passwordValid && _confirmValid;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nameCtrl = TextEditingController(text: user.name);
    _phoneCtrl = TextEditingController(text: user.phone ?? '');
    _birthDate = user.birthDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
      locale: const Locale('ko'),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
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
    if (picked != null) setState(() => _birthDate = picked);
  }

  void _save() {
    if (!_canSave) return;
    final user = ref.read(currentUserProvider);
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final newPassword = _passwordCtrl.text;
    final updated = user.copyWith(
      name: name.isEmpty ? user.name : name,
      avatarInitials:
          name.isNotEmpty ? name[0].toUpperCase() : user.avatarInitials,
      phone: phone.isEmpty ? user.phone : phone,
      birthDate: _birthDate,
      clearBirthDate: _birthDate == null,
      password: newPassword.isEmpty ? user.password : newPassword,
    );
    // 로컬 상태를 동기적으로 반영하므로(첫 await 이전) 저장 완료를 기다리지
    // 않고 바로 뒤로 가도 최신 값이 보인다.
    ref.read(authNotifierProvider).updateProfile(updated);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
              children: [
                _EditProfileHeader(onBack: () => context.pop()),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LabeledField(
                          label: '이름',
                          controller: _nameCtrl,
                          hint: '이름을 입력해줘',
                        ),
                        const SizedBox(height: 14),
                        _ReadOnlyField(label: '아이디', value: user.username),
                        const SizedBox(height: 14),
                        _ReadOnlyField(label: '이메일', value: user.email),
                        const SizedBox(height: 14),
                        _LabeledField(
                          label: '비밀번호',
                          controller: _passwordCtrl,
                          hint: '변경할 때만 입력해줘',
                          obscureText: _hidePassword,
                          onChanged: (_) => setState(() {}),
                          suffix: _EyeToggle(
                            hidden: _hidePassword,
                            onTap: () =>
                                setState(() => _hidePassword = !_hidePassword),
                          ),
                          errorText:
                              _passwordCtrl.text.isNotEmpty && !_passwordValid
                                  ? '영문, 숫자를 포함해 8자 이상이어야 해.'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        _LabeledField(
                          label: '비밀번호 확인',
                          controller: _confirmPasswordCtrl,
                          hint: '비밀번호를 한 번 더 입력해줘',
                          obscureText: _hideConfirmPassword,
                          onChanged: (_) => setState(() {}),
                          suffix: _EyeToggle(
                            hidden: _hideConfirmPassword,
                            onTap: () => setState(() =>
                                _hideConfirmPassword = !_hideConfirmPassword),
                          ),
                          errorText: _confirmPasswordCtrl.text.isNotEmpty &&
                                  !_confirmValid
                              ? '비밀번호가 서로 달라. 다시 확인해줘.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        _LabeledField(
                          label: '전화번호',
                          controller: _phoneCtrl,
                          hint: '010-0000-0000',
                          keyboardType: TextInputType.phone,
                          formatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                            _PhoneNumberFormatter(),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _BirthDateField(
                          date: _birthDate,
                          onTap: _pickBirthDate,
                        ),
                        const SizedBox(height: 28),
                        _SaveCta(onTap: _save, enabled: _canSave),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 헤더 ───────────────────────────────────────────────────────────────────
class _EditProfileHeader extends StatelessWidget {
  const _EditProfileHeader({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const Expanded(
            child: Text(
              '내 정보 수정',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 48), // 뒤로가기 버튼과 균형 맞추기용 더미 폭
        ],
      ),
    );
  }
}

// ── 라벨 + 값 공통 프레임 ────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// ── 수정 가능한 필드 (이름 · 비밀번호) ───────────────────────────────────
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscureText = false,
    this.suffix,
    this.errorText,
    this.onChanged,
    this.keyboardType,
    this.formatters,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final Widget? suffix;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        TextField(
          controller: controller,
          obscureText: obscureText,
          onChanged: onChanged,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          cursorColor: AppColors.green,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
            filled: true,
            fillColor: AppColors.grey,
            suffixIcon: suffix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.green, width: 1.5),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: const TextStyle(
                color: AppColors.red,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

class _EyeToggle extends StatelessWidget {
  const _EyeToggle({required this.hidden, required this.onTap});
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: Colors.white.withValues(alpha: 0.4),
      ),
    );
  }
}

// ── 잠긴 필드 (아이디 · 이메일) ─────────────────────────────────────────
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: AppColors.grey.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.lock_outline_rounded,
                  size: 16, color: Colors.white.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 생년월일 (탭하면 날짜 선택) ───────────────────────────────────────────
class _BirthDateField extends StatelessWidget {
  const _BirthDateField({required this.date, required this.onTap});
  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('생년월일'),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: AppColors.grey,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    date != null ? _formatDate(date!) : '생년월일을 선택해줘',
                    style: TextStyle(
                      color: date != null
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.3),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.calendar_today_outlined,
                    size: 18, color: Colors.white.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.year}. ${d.month.toString().padLeft(2, '0')}. '
    '${d.day.toString().padLeft(2, '0')}';

// ── 저장 버튼 ──────────────────────────────────────────────────────────────
class _SaveCta extends StatelessWidget {
  const _SaveCta({required this.onTap, this.enabled = true});
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.green
              : AppColors.green.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(
          '저장',
          style: TextStyle(
              color: AppColors.black.withValues(alpha: enabled ? 1 : 0.5),
              fontSize: 15,
              fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// 입력하는 동안 010-1234-5678 형태로 하이픈을 자동으로 붙여준다.
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
