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

  @override
  Future<void> requestEmailVerification(String email) async =>
      requested.add(email);

  @override
  Future<bool> confirmEmailVerification({
    required String email,
    required String code,
  }) async =>
      code == _validCode;
}

void main() {
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
    expect(find.text('인증된 이메일'), findsNothing);
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
    expect(find.text('인증된 이메일'), findsNothing);
    expect(find.text('인증 코드가 맞지 않아. 다시 확인해줘.'), findsOneWidget);
    await tester.enterText(fields.at(1), _validCode);
    await tester.pump();
    await tester.tap(find.text('인증하기'));
    await tester.pumpAndSettle();
    expect(find.text('인증 완료'), findsOneWidget);
    expect(find.text('인증된 이메일'), findsOneWidget);
    expect(tester.widget<TextField>(fields.at(1)).focusNode!.hasFocus, isFalse);
    await tester.enterText(fields.at(0), 'different@bpt.app');
    await tester.pump();
    expect(find.text('인증된 이메일'), findsNothing);
    expect(tester.widget<TextField>(fields.at(1)).enabled, isFalse);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
