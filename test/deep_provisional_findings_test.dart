import 'dart:convert';
import 'dart:io';
import 'package:bpt/features/workout/screens/deep_analysis_report_screen.dart';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sample() {
  final fault = <String, dynamic>{
    'rep': 1,
    'key': 'symmetry',
    'metric': 'symmetryMaxDeg',
    'value': 26.5,
    'severity': 'critical',
    'title': '양쪽 움직임을 맞춰 봐',
    'body': '좌우 관절 각도가 달랐어. 이 구간을 천천히 확인해 보자.',
    'confidence': .9,
    'threshold': 15,
    'evidence': [
      {'t': .5, 'frame': 15}
    ],
  };
  return {
    'rules': {'placeholder': true},
    'faults': [fault],
    'summary': {'faultCount': 1},
    'timeline': [
      {
        'rep': null,
        't': 0,
        'severity': 'critical',
        'title': '총평',
        'body': '표시한 구간부터 같이 확인해 보자!'
      },
      {...fault, 't': .5},
    ],
    'reps': [
      {
        'repIndex': 1,
        'confidence': .9,
        'primaryJoint': 'elbow',
        'faults': [fault]
      }
    ],
  };
}

Future<void> mount(WidgetTester tester, Map<String, dynamic> report,
    List<Duration> seeks) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: DeepAnalysisReport(
              report: report,
              video: const SizedBox(height: 10),
              onSeek: seeks.add))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'placeholder findings remain observations, not posture instructions',
      (tester) async {
    final report = sample();
    final original = jsonEncode(report);
    final seeks = <Duration>[];
    await mount(tester, report, seeks);
    expect(find.text('양쪽 움직임을 맞춰 봐'), findsNothing);
    expect(find.textContaining('좌우 관절각 최대 차이 26.5°'), findsOneWidget);
    expect(find.text('측정 기록 · 잠정 소견 1개'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.textContaining('좌우 관절각 최대 차이 26.5°'))
            .style
            ?.color,
        Colors.lightBlueAccent);
    await tester.tap(find.textContaining('좌우 관절각 최대 차이 26.5°'));
    expect(seeks.last, const Duration(milliseconds: 500));
    await tester.tap(find.text('1회 · 자세히 보기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('측정 근거 보기'), 250);
    expect(find.textContaining('양쪽 움직임을 맞춰 봐'), findsNothing);
    expect(find.textContaining('26.5° · 측정 근거 보기'), findsOneWidget);
    final button = find.ancestor(
        of: find.textContaining('측정 근거 보기'), matching: find.byType(TextButton));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    expect(seeks,
        [const Duration(milliseconds: 500), const Duration(milliseconds: 500)]);
    expect(jsonEncode(report), original);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unknown finding stays neutral and informational timeline survives malformed optional rules',
      (tester) async {
    final report = sample();
    report['rules'] = 'malformed optional metadata';
    (report['faults'] as List).first['metric'] = 'future_metric';
    (report['timeline'] as List).add({
      'rep': 1,
      't': .8,
      'severity': 'info',
      'title': '관측 가능한 반복',
      'body': '일부 관절의 추정값은 남아 있어.'
    });
    await mount(tester, report, []);
    expect(find.text('잠정 측정 소견'), findsOneWidget);
    expect(find.text('관측 가능한 반복'), findsOneWidget);
    expect(find.text('일부 관절의 추정값은 남아 있어.'), findsOneWidget);
    expect(find.textContaining('양쪽 움직임을 맞춰 봐'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  final path = Platform.environment['BPT_EXPECTED_CURRENT_REPORT_FILE'];
  testWidgets(
      'actual ten placeholder events preserved without prescriptive display',
      (tester) async {
    final bytes = File(path!).readAsBytesSync();
    expect(sha256.convert(bytes).toString(),
        Platform.environment['BPT_EXPECTED_CURRENT_REPORT_SHA256']);
    final report =
        (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
    final before = jsonEncode(report);
    expect(report['faults'], hasLength(10));
    expect(
        (report['faults'] as List)
            .every((f) => f['metric'] == 'symmetryMaxDeg'),
        isTrue);
    final seeks = <Duration>[];
    await mount(tester, report, seeks);
    expect(find.textContaining('양쪽 움직임을 맞춰 봐'), findsNothing);
    expect(find.text('측정 기록 · 잠정 소견 10개'), findsOneWidget);
    expect(find.textContaining('자세의 정상·이상 판정은 보류했어'), findsWidgets);
    expect(jsonEncode(report), before);
    expect(tester.takeException(), isNull);
  }, skip: path == null);
}
