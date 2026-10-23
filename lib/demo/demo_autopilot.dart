// TRIAL BRANCH ONLY — demo recording autopilot. Runs the whole app flow by itself (sign up → onboarding → body scan →
// barbell row 3 sets → result → calendar) when Documents/bpt_demo.json has "BPT_DEMO_AUTOPILOT": "1". Needed because
// `flutter test` cannot drive a wirelessly connected iPhone. Taps go through the normal gesture path
// (LiveWidgetController), text is put into the fields' controllers. DEMO_ID / DEMO_PW come from the same file; the
// password is removed from the file as soon as it is read. Progress: Documents/demo/flow_steps.log (never the password).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bpt/features/onboarding/services/calibration_upload_service.dart';
import 'package:bpt/features/onboarding/widgets/body_mesh_reveal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DemoAutopilot {
  DemoAutopilot._(this._id, this._pw, this._startDelay, {this.queryJob});

  final String? queryJob;

  /// True while an autopilot run is going (the analysis screen then waits longer for the fit job).
  static bool active = false;

  final String _id;
  final String _pw;
  final double _startDelay; // DEMO_START_DELAY s: time to accept the screen-recording prompt before the first tap
  final _c = LiveWidgetController(WidgetsBinding.instance);

  static String _docs = ''; // app Documents (HOME is not in the Dart environment on iOS)

  /// Reads the demo config before runApp. When it asks for the autopilot, clears saved login / onboarding state
  /// (fresh sign-up) and returns the pilot; otherwise returns null and changes nothing.
  static Future<DemoAutopilot?> prepare(SharedPreferences prefs) async {
    try {
      _docs = (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      return null;
    }
    final file = File('$_docs/bpt_demo.json');
    if (!file.existsSync()) return null;
    final Map<String, dynamic> config;
    try {
      config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final queryJob = '${config['DEMO_QUERY_JOB'] ?? ''}';
    if (queryJob.isNotEmpty) {
      // One lookup of an earlier job with the account still signed in on the phone (no sign-up, no reset).
      config.remove('DEMO_QUERY_JOB');
      file.writeAsStringSync(jsonEncode(config));
      return DemoAutopilot._('', '', 4, queryJob: queryJob);
    }
    if ('${config['BPT_DEMO_AUTOPILOT']}' != '1') return null;
    final id = '${config['DEMO_ID'] ?? ''}', pw = '${config['DEMO_PW'] ?? ''}';
    config.remove('DEMO_PW');
    config['BPT_DEMO_AUTOPILOT'] = '0'; // one run per config write
    file.writeAsStringSync(jsonEncode(config));
    if (id.isEmpty || pw.isEmpty) {
      _log('no DEMO_ID / DEMO_PW');
      return null;
    }
    await prefs.clear();
    return DemoAutopilot._(id, pw, double.tryParse('${config['DEMO_START_DELAY'] ?? ''}') ?? 4);
  }

  Future<void> run() async {
    if (queryJob != null) return _queryJob(queryJob!);
    active = true;
    try {
      await _run();
      _log('done');
    } catch (e) {
      _log('FAILED: $e');
    }
  }

  /// One fit-job poll answer into flow_steps.log: status, progress, error, seconds since polling began.
  /// Never the token, the result body or any (signed) URL.
  static void logJob(String jobId, DateTime started, {CalibrationJob? job, String? error}) {
    if (!active && _docs.isEmpty) return;
    final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
    final detail = job == null
        ? error ?? ''
        : 'status=${job.status} progress=${job.progressRate} error=${job.error ?? '-'}';
    _log('job $jobId +${seconds.toStringAsFixed(1)}s $detail');
  }

  Future<void> _queryJob(String jobId) async {
    await _pause(4);
    try {
      final element = find.byType(MaterialApp).evaluate().first;
      final service = ProviderScope.containerOf(element).read(calibrationUploadServiceProvider);
      final job = await service.fetchJob(jobId);
      logJob(jobId, DateTime.now(), job: job);
    } on CalibrationUploadException catch (e) {
      _log('job $jobId query failed: ${e.message}');
    } catch (e) {
      _log('job $jobId query failed: ${e.runtimeType}');
    }
  }

  static void _log(String line) {
    final text = '${DateTime.now().toIso8601String()} $line';
    debugPrint('[DemoAutopilot] $text');
    try {
      final dir = Directory('$_docs/demo')..createSync(recursive: true);
      File('${dir.path}/flow_steps.log').writeAsStringSync('$text\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _pause(double seconds) => Future.delayed(Duration(milliseconds: (seconds * 1000).round()));

  String _screenText() => find
      .byType(Text)
      .evaluate()
      .take(40)
      .map((e) => (e.widget as Text).data ?? '')
      .where((t) => t.isNotEmpty)
      .join(' | ');

  Future<void> _waitFor(Finder finder, String label, {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (finder.evaluate().isNotEmpty) return;
      await _pause(0.25);
    }
    _log('TIMEOUT waiting for $label; on screen: ${_screenText()}');
    throw StateError('timed out waiting for $label');
  }

  Future<void> _tapText(String text, {Duration timeout = const Duration(seconds: 30)}) async {
    final f = find.text(text);
    await _waitFor(f, text, timeout: timeout);
    await _c.ensureVisible(f.first);
    await _pause(0.3);
    await _c.tap(f.first);
    _log('tap $text');
    await _pause(0.8);
  }

  Future<void> _tap(Finder f, String label) async {
    await _waitFor(f, label);
    await _c.ensureVisible(f.first);
    await _pause(0.3);
    await _c.tap(f.first);
    _log('tap $label');
    await _pause(0.8);
  }

  /// Body card values: tap the shown number, put the new one in the inline field, unfocus (commits it).
  Future<void> _editValue(String shown, String value) async {
    await _tapText(shown);
    await _waitFor(find.byType(TextField), 'edit $shown');
    final field = find.byType(TextField).evaluate().first.widget as TextField;
    field.controller?.text = value;
    await _pause(0.6);
    FocusManager.instance.primaryFocus?.unfocus();
    _log('set $shown -> $value');
    await _pause(0.8);
  }

  void _type(int index, String value, {bool secret = false}) {
    final field = find.byType(TextField).evaluate().elementAt(index).widget as TextField;
    field.controller?.text = value;
    field.onChanged?.call(value);
    _log('type field $index ${secret ? '(hidden)' : value}');
  }

  Future<void> _run() async {
    _log('start (id $_id)');
    await _pause(_startDelay);

    // 1. 회원가입
    final signUpLink = find.textContaining('회원가입 하기', findRichText: true);
    await _waitFor(signUpLink, 'sign-up link', timeout: const Duration(seconds: 60));
    await _tap(signUpLink, 'sign-up link');
    await _waitFor(find.byType(TextField), 'sign-up fields');
    _type(0, '데모');
    await _pause(0.5);
    _type(1, '$_id@example.com');
    await _pause(0.5);
    _type(2, _id);
    await _pause(0.5);
    await _tapText('중복확인');
    await _waitFor(find.text('확인 완료'), 'id available');
    _type(3, _pw, secret: true);
    await _pause(0.5);
    _type(4, _pw, secret: true);
    await _pause(0.5);
    _type(5, '01000000000');
    FocusManager.instance.primaryFocus?.unfocus();
    await _pause(1);
    await _tap(find.byType(TextField).at(6), 'birth date');
    await _tapText('확인', timeout: const Duration(seconds: 10)); // date picker keeps its initial date (20 years ago)
    await _tapText('이용약관 및 개인정보 처리방침에 동의');
    await _tapText('가입하기');
    await _pause(3);

    // 2. 온보딩
    await _tapText('남자', timeout: const Duration(seconds: 60));
    await _tapText('다음');
    await _pause(1.5);
    await _editValue('176', '177'); // 키 (default 176)
    await _editValue('71.5', '95'); // 몸무게 (default 71.5)
    await _pause(1);
    await _tapText('다음');
    await _pause(1.5);
    await _tapText('체형 교정');
    await _tapText('체형 측정하러 가기');
    await _pause(1.5);
    await _tapText('카메라 켜기');
    _log('calibration started');

    // 3. 체형 촬영(영상 입력) → 업로드·분석(메시 준비 포함) → '신체분석 완료!'(메시 카드) 또는 기존 결과 화면
    final done = find.text('신체분석 완료!');
    final home = find.text('홈으로 가기');
    final end = DateTime.now().add(const Duration(minutes: 7));
    while (DateTime.now().isBefore(end) && done.evaluate().isEmpty && home.evaluate().isEmpty) {
      await _pause(0.5);
    }
    if (done.evaluate().isNotEmpty) {
      _log('body analysis done screen');
      await _pause(1.5);
      await BodyMeshReveal.demoSpin(turns: 1, seconds: 7); // returns at once; the turn runs natively for 7 s
      await _pause(8.5);
      await _tapText('넘어가기');
    } else {
      _log('old result screen');
      await _tapText('홈으로 가기', timeout: const Duration(seconds: 30));
    }
    await _pause(2);

    // 4. 바벨로우 3세트
    await _tapText('오늘은 무슨 운동을 할래?', timeout: const Duration(seconds: 60));
    await _tapText('바벨로우');
    await _pause(1.5);
    // target reps = the clip's 11 reps (default 12): the uniform reps stepper is the second '−' (after set count)
    await _tap(find.byIcon(Icons.remove).at(1), 'reps -1');
    await _pause(1);
    await _tapText('시작해볼까?');
    await _tapText('끝! 시작할게');
    for (var set = 1; set <= 2; set++) {
      await _tapText('바로 할래', timeout: const Duration(minutes: 3));
      _log('set ${set + 1} started');
    }
    await _tapText('결과 보러 가기', timeout: const Duration(minutes: 3));
    await _pause(5);

    // 5. 결과 아래로 훑고, 기록(달력)
    final scroll = find.byType(Scrollable);
    if (scroll.evaluate().isNotEmpty) {
      await _c.drag(scroll.first, const Offset(0, -400));
      await _pause(2);
      await _c.drag(scroll.first, const Offset(0, 400));
      await _pause(1);
    }
    final history = find.text('기록 보기');
    final nav = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_NavIcon');
    if (history.evaluate().isNotEmpty) {
      await _tap(history, '기록 보기');
      await _pause(6);
    } else if (nav.evaluate().length > 1) {
      await _c.tap(nav.at(1));
      _log('tap calendar');
      await _pause(6);
    } else {
      _log('calendar nav not on this screen: ${_screenText()}');
    }
  }
}
