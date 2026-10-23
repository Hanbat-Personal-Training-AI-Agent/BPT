// TRIAL BRANCH ONLY: drives the whole app for the demo screen recording (sign up → onboarding → body scan →
// barbell row 3 sets → workout history). Camera input comes from Documents/bpt_demo.json (BPT_CALIB_VIDEO,
// BPT_CAMERA_VIDEO …), written to the phone before the run.
//
//   flutter test integration_test/demo_flow_test.dart -d <udid> \
//     --dart-define=DEMO_ID=<id> --dart-define-from-file=<private file with {"DEMO_PW": "…"}>
//
// The password never goes into git, docs or logs: it only lives in that private file on the Mac.
import 'package:bpt/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const demoId = String.fromEnvironment('DEMO_ID');
const demoPw = String.fromEnvironment('DEMO_PW');

Future<void> waitFor(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 30), String? label}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('timed out waiting for ${label ?? finder}');
}

Future<void> tapText(WidgetTester tester, String text, {Duration timeout = const Duration(seconds: 30)}) async {
  final f = find.text(text);
  await waitFor(tester, f, timeout: timeout, label: text);
  await tester.ensureVisible(f.first);
  await tester.tap(f.first);
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> pause(WidgetTester tester, double seconds) async {
  final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo flow', (tester) async {
    expect(demoId.isNotEmpty && demoPw.isNotEmpty, isTrue, reason: 'pass DEMO_ID and DEMO_PW');
    app.main();
    await pause(tester, 4);

    // 1. 회원가입
    await tapText(tester, '회원가입 하기', timeout: const Duration(seconds: 60));
    await waitFor(tester, find.byType(TextField), label: 'sign-up fields');
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '데모');
    await tester.enterText(fields.at(1), '$demoId@example.com');
    await tester.enterText(fields.at(2), demoId);
    await tapText(tester, '중복확인');
    await pause(tester, 2);
    await tester.enterText(fields.at(3), demoPw);
    await tester.enterText(fields.at(4), demoPw);
    await tester.enterText(fields.at(5), '01000000000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pause(tester, 1);
    await tapText(tester, '이용약관 및 개인정보 처리방침에 동의');
    final submit = find.widgetWithText(ElevatedButton, '회원가입');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await pause(tester, 3);

    // 2. 온보딩
    await tapText(tester, '남자', timeout: const Duration(seconds: 60));
    await tapText(tester, '다음');
    await pause(tester, 1.5);
    await tapText(tester, '다음');
    await pause(tester, 1.5);
    await tapText(tester, '체형 교정');
    await tapText(tester, '체형 측정하러 가기');
    await pause(tester, 1.5);
    await tapText(tester, '카메라 켜기');

    // 3. 체형 촬영(캘리브레이션, 영상 입력) → 업로드·분석 → 결과
    await tapText(tester, '홈으로 가기', timeout: const Duration(minutes: 6));
    await pause(tester, 2);

    // 4. 바벨로우 3세트(기본 3세트 × 12회, 영상 입력)
    await tapText(tester, '오늘은 무슨 운동을 할래?', timeout: const Duration(seconds: 60));
    await tapText(tester, '바벨로우');
    await pause(tester, 1.5);
    await tapText(tester, '시작해볼까?');
    await tapText(tester, '끝! 시작할게');
    for (var set = 1; set <= 2; set++) {
      await tapText(tester, '바로 할래', timeout: const Duration(minutes: 3));
    }
    await tapText(tester, '결과 보러 가기', timeout: const Duration(minutes: 3));
    await pause(tester, 4);

    // 5. 운동 기록(달력)
    final scroll = find.byType(Scrollable);
    if (scroll.evaluate().isNotEmpty) {
      await tester.drag(scroll.first, const Offset(0, -400));
      await pause(tester, 2);
    }
    await tester.pageBack();
    await pause(tester, 2);
    final nav = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_NavIcon');
    if (nav.evaluate().length > 1) {
      await tester.tap(nav.at(1));
      await pause(tester, 5);
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
