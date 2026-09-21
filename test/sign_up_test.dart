import 'package:bpt/core/constants/route_constants.dart';
import 'package:bpt/core/theme/app_colors.dart';
import 'package:bpt/features/auth/providers/sign_up_provider.dart';
import 'package:bpt/features/auth/screens/sign_up_screen.dart';
import 'package:bpt/features/onboarding/screens/onboarding_gender_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('id duplicate check and submit gating follow the mock rules', () {
    final notifier = SignUpNotifier();
    addTearDown(notifier.dispose);

    notifier.changeName('김');
    expect(notifier.state.nameValid, isFalse); // under 2 chars
    notifier.changeName('김지훈');
    expect(notifier.state.nameValid, isTrue);

    notifier.changeEmail('jihoon@bpt.app');
    notifier.changeId('admin');
    notifier.checkIdDuplicate();
    expect(notifier.state.idCheck, IdCheckStatus.taken);
    expect(notifier.state.canSubmit, isFalse);

    notifier.changeId('jihoon_kim');
    // Editing the id after a check must reset the check result.
    expect(notifier.state.idCheck, IdCheckStatus.none);
    notifier.checkIdDuplicate();
    expect(notifier.state.idCheck, IdCheckStatus.available);

    notifier.changePassword('1234567');
    expect(notifier.state.passwordValid, isFalse); // under 8 chars
    notifier.changePassword('12345678');
    expect(notifier.state.passwordValid, isFalse); // digits only
    notifier.changePassword('abcdefgh');
    expect(notifier.state.passwordValid, isFalse); // letters only
    notifier.changePassword('abcd1234');
    expect(notifier.state.passwordValid, isTrue);
    notifier.changeConfirmPassword('abcd1234');
    notifier.changePhone('01028417756');
    expect(notifier.state.canSubmit, isFalse); // no birth date / terms yet

    notifier.setBirthDate(DateTime(1999, 4, 12));
    expect(notifier.state.canSubmit, isFalse); // terms not agreed

    notifier.toggleAgreed();
    expect(notifier.state.canSubmit, isTrue);
  });

  testWidgets('sign up form enables fields and the submit button in order',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const SignUpScreen()),
      GoRoute(
        path: RouteConstants.onboardingGender,
        builder: (context, state) => const OnboardingGenderScreen(),
      ),
    ]);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));

    final fields = find.byType(TextField);
    // name, email, id, password, confirm, phone, birth date
    expect(fields, findsNWidgets(7));

    await tester.enterText(fields.at(0), '김지훈');
    await tester.enterText(fields.at(1), 'jihoon@bpt.app');
    final border = tester
        .widget<TextField>(fields.at(1))
        .decoration!
        .focusedBorder! as OutlineInputBorder;
    expect(border.borderSide.color, AppColors.green);

    await tester.enterText(fields.at(2), 'admin');
    await tester.pump();
    await tester.tap(find.text('중복확인'));
    await tester.pump();
    expect(find.text('이미 사용 중인 아이디예요. 다른 아이디를 입력해줘.'), findsOneWidget);

    await tester.enterText(fields.at(2), 'jihoon_kim');
    await tester.pump();
    // editing after a failed check clears the error and re-enables the button
    expect(find.text('이미 사용 중인 아이디예요. 다른 아이디를 입력해줘.'), findsNothing);
    await tester.tap(find.text('중복확인'));
    await tester.pump();
    expect(find.text('확인 완료'), findsOneWidget);

    await tester.enterText(fields.at(3), 'abcd1234');
    await tester.enterText(fields.at(4), '00000000');
    await tester.tap(fields.at(5)); // blur the confirm field
    await tester.pump();
    expect(find.text('비밀번호가 서로 달라. 다시 확인해줘.'), findsOneWidget);
    // Mismatched: both password fields show a visibility toggle.
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
    expect(tester.widget<TextField>(fields.at(4)).obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility_outlined).last);
    await tester.pump();
    expect(tester.widget<TextField>(fields.at(4)).obscureText, isFalse);

    await tester.enterText(fields.at(4), 'abcd1234');
    await tester.pump();
    expect(find.text('비밀번호가 서로 달라. 다시 확인해줘.'), findsNothing);
    // Matched: the confirm field swaps its toggle for a check mark.
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.enterText(fields.at(5), '01028417756');
    await tester.pump();

    final submitFinder = find.widgetWithText(ElevatedButton, '가입하기');
    expect(tester.widget<ElevatedButton>(submitFinder).onPressed, isNull);

    // Simulate picking a birth date directly through the provider, since
    // showDatePicker opens a real dialog that isn't worth driving here.
    final context = tester.element(find.byType(SignUpScreen));
    ProviderScope.containerOf(context, listen: false)
        .read(signUpProvider.notifier)
        .setBirthDate(DateTime(1999, 4, 12));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(submitFinder).onPressed, isNull);

    await tester.tap(find.text('이용약관 및 개인정보 처리방침에 동의'));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(submitFinder).onPressed, isNotNull);

    await tester.tap(submitFinder);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingGenderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'invalid formats show an inline error only after leaving the field',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SignUpScreen())));

    final fields = find.byType(TextField);
    const name = 0, email = 1, id = 2, password = 3, phone = 5;

    // Typing an invalid email shows no error until focus leaves the field.
    await tester.enterText(fields.at(email), 'not-an-email');
    await tester.pump();
    expect(find.text('올바른 이메일 형식이 아니야.'), findsNothing);
    await tester.tap(fields.at(id));
    await tester.pump();
    expect(find.text('올바른 이메일 형식이 아니야.'), findsOneWidget);

    // Fixing it clears the error immediately (no need to blur again).
    await tester.enterText(fields.at(email), 'jihoon@bpt.app');
    await tester.pump();
    expect(find.text('올바른 이메일 형식이 아니야.'), findsNothing);

    await tester.enterText(fields.at(password), '123');
    await tester.pump();
    expect(find.text('영문, 숫자를 포함해 8자 이상이어야 해.'), findsNothing);
    await tester.tap(fields.at(phone));
    await tester.pump();
    expect(find.text('영문, 숫자를 포함해 8자 이상이어야 해.'), findsOneWidget);

    await tester.enterText(fields.at(phone), '123');
    await tester.pump();
    expect(find.text('전화번호를 정확히 입력해줘.'), findsNothing);
    await tester.tap(fields.at(email));
    await tester.pump();
    expect(find.text('전화번호를 정확히 입력해줘.'), findsOneWidget);

    // 이름은 두 글자 이상이어야 한다.
    await tester.enterText(fields.at(name), '김');
    await tester.pump();
    expect(find.text('이름은 두 글자 이상 입력해줘.'), findsNothing);
    await tester.tap(fields.at(email));
    await tester.pump();
    expect(find.text('이름은 두 글자 이상 입력해줘.'), findsOneWidget);
    await tester.enterText(fields.at(name), '김지');
    await tester.pump();
    expect(find.text('이름은 두 글자 이상 입력해줘.'), findsNothing);

    // 아이디는 입력만 하고 중복확인을 안 하면 안내가 뜬다. (이 칸은 위에서 이미
    // 한 번 포커스를 벗어났으므로 다시 입력하는 즉시 안내가 보인다.)
    await tester.enterText(fields.at(id), 'jihoon_kim');
    await tester.pump();
    expect(find.text('아이디 중복확인을 해줘.'), findsOneWidget);
    await tester.tap(find.text('중복확인'));
    await tester.pump();
    expect(find.text('아이디 중복확인을 해줘.'), findsNothing);

    // 8자 이상이어도 숫자만이면 여전히 오류.
    await tester.enterText(fields.at(password), '12345678');
    await tester.pump();
    expect(find.text('영문, 숫자를 포함해 8자 이상이어야 해.'), findsOneWidget);
    await tester.enterText(fields.at(password), 'abcd1234');
    await tester.pump();
    expect(find.text('영문, 숫자를 포함해 8자 이상이어야 해.'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tapping empty space (not just another field) also blurs and shows the error',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SignUpScreen())));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'not-an-email');
    await tester.pump();
    expect(find.text('올바른 이메일 형식이 아니야.'), findsNothing);

    // Tap a plain, non-interactive label instead of another field —
    // this must still blur the email field via the scaffold's
    // tap-outside handling.
    await tester.tap(find.text('회원가입'));
    await tester.pump();
    expect(find.text('올바른 이메일 형식이 아니야.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
