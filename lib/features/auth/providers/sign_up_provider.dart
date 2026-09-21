import 'package:flutter_riverpod/flutter_riverpod.dart';

/// UI preview only. Never creates a Firebase account.
/// 아이디 목업 중복확인용으로 이미 사용 중인 것으로 취급하는 값들.
const signUpTakenIds = ['test', 'admin', 'bpt'];

enum IdCheckStatus { none, available, taken }

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
  bool get emailValid => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  bool get passwordValid =>
      password.length >= 8 &&
      RegExp(r'[A-Za-z]').hasMatch(password) &&
      RegExp(r'\d').hasMatch(password);
  bool get confirmValid =>
      confirmPassword.isNotEmpty && confirmPassword == password;
  bool get phoneValid =>
      RegExp(r'^01[016789]\d{7,8}$').hasMatch(phone.replaceAll('-', ''));

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
  SignUpNotifier() : super(const SignUpState());

  void changeName(String value) => state = state.copyWith(name: value);

  void changeEmail(String value) => state = state.copyWith(email: value);

  void changeId(String value) => state = state.copyWith(
        id: value,
        idCheck: IdCheckStatus.none,
      );

  void checkIdDuplicate() {
    if (state.id.trim().isEmpty) return;
    state = state.copyWith(
      idCheck: signUpTakenIds.contains(state.id.trim())
          ? IdCheckStatus.taken
          : IdCheckStatus.available,
    );
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
  (ref) => SignUpNotifier(),
);
