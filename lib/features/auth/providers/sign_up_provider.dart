import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../services/auth_service.dart';

/// 아이디 규칙: 영문 소문자·숫자 4~20자. (백엔드는 _ 까지 허용하지만 앱에서는 받지 않는다)
final authIdPattern = RegExp(r'^[a-z0-9]{4,20}$');

enum IdCheckStatus { none, checking, available, taken, failed }

class SignUpState {
  const SignUpState({
    this.name = '',
    this.email = '',
    this.id = '',
    this.idCheck = IdCheckStatus.none,
    this.password = '',
    this.confirmPassword = '',
    this.phone = '',
    this.birthDate,
    this.agreed = false,
  });

  final String name;
  final String email;
  final String id;
  final IdCheckStatus idCheck;
  final String password;
  final String confirmPassword;
  final String phone;
  final DateTime? birthDate;
  final bool agreed;

  bool get nameValid => name.trim().length >= 2;
  bool get idFormatValid => authIdPattern.hasMatch(id.trim());
  bool get emailValid => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  bool get passwordValid =>
      password.length >= 8 &&
      RegExp(r'[A-Za-z]').hasMatch(password) &&
      RegExp(r'\d').hasMatch(password);
  bool get confirmValid =>
      confirmPassword.isNotEmpty && confirmPassword == password;
  bool get phoneValid =>
      RegExp(r'^01[016789]\d{7,8}$').hasMatch(phone.replaceAll('-', ''));

  /// 백엔드 형식(010-1234-5678)으로 맞춘 전화번호
  String get formattedPhone {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    final mid = d.length - 7; // 가운데 자리: 3자리(10자리 번호) 또는 4자리
    return '${d.substring(0, 3)}-${d.substring(3, 3 + mid)}-${d.substring(3 + mid)}';
  }

  bool get canSubmit =>
      nameValid &&
      emailValid &&
      idCheck == IdCheckStatus.available &&
      passwordValid &&
      confirmValid &&
      phoneValid &&
      birthDate != null &&
      agreed;

  SignUpState copyWith({
    String? name,
    String? email,
    String? id,
    IdCheckStatus? idCheck,
    String? password,
    String? confirmPassword,
    String? phone,
    DateTime? birthDate,
    bool? agreed,
  }) =>
      SignUpState(
        name: name ?? this.name,
        email: email ?? this.email,
        id: id ?? this.id,
        idCheck: idCheck ?? this.idCheck,
        password: password ?? this.password,
        confirmPassword: confirmPassword ?? this.confirmPassword,
        phone: phone ?? this.phone,
        birthDate: birthDate ?? this.birthDate,
        agreed: agreed ?? this.agreed,
      );
}

class SignUpNotifier extends StateNotifier<SignUpState> {
  SignUpNotifier(this._authService) : super(const SignUpState());

  final AuthService _authService;

  void changeName(String value) => state = state.copyWith(name: value);

  void changeEmail(String value) => state = state.copyWith(email: value);

  void changeId(String value) => state = state.copyWith(
        id: value,
        idCheck: IdCheckStatus.none,
      );

  /// 서버에 아이디 사용 가능 여부를 묻는다.
  Future<void> checkIdDuplicate() async {
    final id = state.id.trim();
    if (!state.idFormatValid) return;
    state = state.copyWith(idCheck: IdCheckStatus.checking);
    IdCheckStatus result;
    try {
      final available = await _authService.checkUsername(id);
      result = available ? IdCheckStatus.available : IdCheckStatus.taken;
    } on ApiException {
      result = IdCheckStatus.failed;
    }
    // 확인하는 사이에 아이디를 바꿨으면 결과를 버린다.
    if (!mounted || state.id.trim() != id) return;
    state = state.copyWith(idCheck: result);
  }

  void changePassword(String value) => state = state.copyWith(password: value);

  void changeConfirmPassword(String value) =>
      state = state.copyWith(confirmPassword: value);

  void changePhone(String value) => state = state.copyWith(phone: value);

  void setBirthDate(DateTime date) => state = state.copyWith(birthDate: date);

  void toggleAgreed() => state = state.copyWith(agreed: !state.agreed);
}

final signUpProvider =
    StateNotifierProvider.autoDispose<SignUpNotifier, SignUpState>(
  (ref) => SignUpNotifier(ref.watch(authServiceProvider)),
);
