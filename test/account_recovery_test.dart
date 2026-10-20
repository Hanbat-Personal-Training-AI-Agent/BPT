import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/core/theme/app_colors.dart';
import 'package:bpt/features/auth/providers/account_recovery_provider.dart';
import 'package:bpt/features/auth/screens/account_recovery_screen.dart';
import 'package:bpt/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _validCode = '418320';

/// 서버 대신 쓰는 가짜 인증 서비스. [_validCode]만 맞는 인증번호로 취급한다.
class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(ApiClient());

  final requested = <String>[];

  /// 아이디를 같이 주면 jihoon / jihoon@bpt.app 만 같은 계정으로 취급한다.
  @override
  Future<void> requestEmailVerification(String email,
      {String? username}) async {
    if (username != null &&
        (username != 'jihoon' || email != 'jihoon@bpt.app')) {
      throw ServerException('User not found', 404, 'USER_NOT_FOUND');
    }
    requested.add(email);
  }

  @override
  Future<({bool verified, String? token})> confirmEmailVerification({
    required String email,
    required String code,
  }) async =>
      (verified: code == _validCode, token: code == _validCode ? 'vt_1' : null);

  final finds = <String>[];

  /// vt_1 토큰은 jihoon 으로 찾아준다.
  @override
  Future<String?> findUsername({required String verificationToken}) async {
    finds.add(verificationToken);
    return 'jihoon';
  }

  final resets = <Map<String, String?>>[];

  /// 'jihoon' 만 jihoon@bpt.app 의 아이디로 취급한다.
  @override
  Future<void> resetPassword({
    required String username,
    required String email,
    required String newPassword,
    String? verificationToken,
  }) async {
    resets.add({
      'username': username,
      'email': email,
      'token': verificationToken,
    });
    if (username != 'jihoon' || email != 'jihoon@bpt.app') {
      throw ServerException('User not found', 404, 'USER_NOT_FOUND');
    }
  }
}

void main() {
  test('password reset sends id, verified email and token; mismatch explains',
      () async {
    final auth = _FakeAuthService();
    final notifier = AccountRecoveryNotifier(auth);
    addTearDown(notifier.dispose);
    expect(
        await notifier.resetPassword(username: 'jihoon', newPassword: 'pw1234'),
        isNull);
    expect(auth.resets, isEmpty); // 인증 전에는 보내지 않는다
    notifier.changeEmail('jihoon@bpt.app');
    await notifier.sendCode();
    await notifier.verifyCode(_validCode);
    expect(
        await notifier.resetPassword(username: 'other', newPassword: 'pw1234'),
        '아이디와 이메일이 맞지 않아. 다시 확인해줘.');
    expect(
        await notifier.resetPassword(username: 'jihoon', newPassword: 'pw1234'),
        isNull);
    expect(auth.resets.last,
        {'username': 'jihoon', 'email': 'jihoon@bpt.app', 'token': 'vt_1'});
  });

  testWidgets('reset page checks id and email before sending the code',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _FakeAuthService();
    await tester.pumpWidget(ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: const MaterialApp(home: AccountRecoveryScreen())));
    await tester.tap(find.text('비밀번호 재설정').first);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    // 아이디 칸이 이메일 칸 위에 있다.
    expect(tester.getTopLeft(find.text('아이디')).dy,
        lessThan(tester.getTopLeft(find.text('이메일')).dy));
    await tester.enterText(fields.at(0), 'other');
    await tester.enterText(fields.at(1), 'jihoon@bpt.app');
    await tester.tap(find.text('인증하기').first);
    await tester.pumpAndSettle();
    // 같은 계정이 아니면 보내지 않는다.
    expect(auth.requested, isEmpty);
    expect(find.text('전송 완료'), findsNothing);
    expect(find.text('아이디와 이메일이 맞지 않아. 다시 확인해줘.'), findsOneWidget);
    await tester.enterText(fields.at(0), 'jihoon');
    await tester.pump();
    await tester.tap(find.text('인증하기').first);
    await tester.pumpAndSettle();
    expect(auth.requested, ['jihoon@bpt.app']);
    expect(find.text('전송 완료'), findsOneWidget);
    await tester.enterText(fields.at(2), _validCode);
    await tester.pump();
    await tester.tap(find.text('인증하기'));
    await tester.pumpAndSettle();
    // 인증이 끝나면 새 비밀번호 칸이 열린다.
    expect(find.text('인증 완료'), findsOneWidget);
    expect(find.text('새 비밀번호'), findsOneWidget);
  });

  test('find id uses the one-time token; reset then asks to verify again',
      () async {
    final auth = _FakeAuthService();
    final notifier = AccountRecoveryNotifier(auth);
    addTearDown(notifier.dispose);
    notifier.changeEmail('jihoon@bpt.app');
    await notifier.sendCode();
    await notifier.verifyCode(_validCode);
    await notifier.findUsername();
    expect(auth.finds, ['vt_1']);
    expect(notifier.state.username, 'jihoon');
    expect(notifier.state.verificationToken, isNull);
    notifier.restartVerification();
    expect(notifier.state.verified, isFalse);
    expect(notifier.state.sent, isFalse);
    expect(notifier.state.email, 'jihoon@bpt.app');
  });

  test('verification requires send and changing email invalidates proof',
      () async {
    final auth = _FakeAuthService();
    final notifier = AccountRecoveryNotifier(auth);
    addTearDown(notifier.dispose);
    await notifier.verifyCode(_validCode);
    expect(notifier.state.verified, isFalse);
    notifier.changeEmail('not-an-email');
    expect(await notifier.sendCode(), isFalse);
    expect(auth.requested, isEmpty);
    notifier.changeEmail('jihoon@bpt.app');
    expect(await notifier.sendCode(), isTrue);
    expect(auth.requested, ['jihoon@bpt.app']);
    await notifier.verifyCode('000000');
    expect(notifier.state.verified, isFalse);
    expect(notifier.state.error, isNotNull);
    await notifier.verifyCode(_validCode);
    expect(notifier.state.verified, isTrue);
    notifier.changeEmail('other@bpt.app');
    expect(notifier.state.sent, isFalse);
    expect(notifier.state.verified, isFalse);
    expect(notifier.state.error, isNull);
  });

  testWidgets('email, code, result and focus follow recovery sequence',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(_FakeAuthService())],
        child: const MaterialApp(home: AccountRecoveryScreen())));
    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(1)).enabled, isFalse);
    expect(find.text('내 아이디'), findsNothing);
    await tester.enterText(fields.at(0), 'jihoon@bpt.app');
    expect(tester.widget<TextField>(fields.at(0)).focusNode!.hasFocus, isTrue);
    final border = tester
        .widget<TextField>(fields.at(0))
        .decoration!
        .focusedBorder! as OutlineInputBorder;
    expect(border.borderSide.color, AppColors.green);
    await tester.tap(find.text('인증하기').first);
    await tester.pumpAndSettle();
    expect(find.text('전송 완료'), findsOneWidget);
    expect(tester.widget<TextField>(fields.at(1)).enabled, isTrue);
    expect(tester.widget<TextField>(fields.at(0)).focusNode!.hasFocus, isFalse);
    expect(tester.widget<TextField>(fields.at(1)).focusNode!.hasFocus, isTrue);
    await tester.enterText(fields.at(1), '000000');
    await tester.pump();
    await tester.tap(find.text('인증하기'));
    await tester.pumpAndSettle();
    expect(find.text('내 아이디'), findsNothing);
    expect(find.text('인증 코드가 맞지 않아. 다시 확인해줘.'), findsOneWidget);
    await tester.enterText(fields.at(1), _validCode);
    await tester.pump();
    await tester.tap(find.text('인증하기'));
    await tester.pumpAndSettle();
    expect(find.text('인증 완료'), findsOneWidget);
    expect(find.text('내 아이디'), findsOneWidget);
    // 이메일이 아니라 찾은 아이디를 보여준다.
    expect(find.text('jihoon'), findsOneWidget);
    expect(tester.widget<TextField>(fields.at(1)).focusNode!.hasFocus, isFalse);
    await tester.enterText(fields.at(0), 'different@bpt.app');
    await tester.pump();
    expect(find.text('내 아이디'), findsNothing);
    expect(tester.widget<TextField>(fields.at(1)).enabled, isFalse);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
