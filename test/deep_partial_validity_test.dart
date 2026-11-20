import 'dart:convert';
import 'dart:io';

import 'package:bpt/features/workout/screens/deep_analysis_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'scorer null measurements stay unavailable while valid joints remain visible',
      (tester) async {
    final report = jsonDecode(
            File('test/fixtures/deep_partial_primary.json').readAsStringSync())
        as Map<String, dynamic>;
    // Show the first rep, without hiding unavailable observations in later rows.
    report['reps'] = [(report['reps'] as List).first];
    report['timeline'] = [];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DeepAnalysisReport(
      report: report,
      video: const SizedBox(height: 10),
      onSeek: (_) {},
    ))));
    await tester.tap(find.text('1회 · 자세히 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ROM 확인 불가 (판정 보류)'), findsOneWidget);
    expect(
        find.textContaining('늘림 확인 불가 · 멈춤 확인 불가 · 수축 확인 불가'), findsOneWidget);
    expect(find.textContaining('몸통(중력 기준) · 최소'), findsOneWidget);
    expect(find.textContaining('위·아래 시점 확인 불가'), findsWidgets);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('\n');
    expect(text, isNot(contains('null')));
    expect(text, isNot(contains('NaN')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing and nonfinite evidence never seek zero; valid evidence seeks exactly',
      (tester) async {
    final seeks = <Duration>[];
    final rep = (jsonDecode(File('test/fixtures/deep_partial_primary.json')
            .readAsStringSync())['reps'] as List)
        .first as Map<String, dynamic>;
    rep['faults'] = [
      {
        'title': '시간 없는 근거',
        'confidence': double.nan,
        'evidence': [
          {'t': null}
        ]
      },
      {
        'title': '유효 근거',
        'confidence': .8,
        'evidence': [
          {'t': 1.25}
        ]
      },
    ];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DeepAnalysisReport(
      report: {
        'reps': [rep],
        'timeline': const [
          {'t': null, 'title': '시각 없음', 'body': '확인 불가'},
          {'t': double.nan, 'title': '비유한 시각', 'body': '확인 불가'},
          {'t': 2.5, 'title': '유효 시각', 'body': '확인 가능'},
        ]
      },
      video: const SizedBox(),
      onSeek: seeks.add,
    ))));
    for (final title in ['시각 없음', '비유한 시각']) {
      await tester.tap(find.text(title));
    }
    expect(seeks, isEmpty);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('deep-analysis-timeline-2')),
        matching: find.byType(ListTile)));
    expect(seeks, [const Duration(milliseconds: 2500)]);
    await tester.ensureVisible(find.text('1회 · 자세히 보기'));
    await tester.tap(find.text('1회 · 자세히 보기'));
    await tester.pumpAndSettle();
    final missing = find.ancestor(
        of: find.textContaining('측정 시간 확인 불가'),
        matching: find.byType(TextButton));
    expect(tester.widget<TextButton>(missing).onPressed, isNull);
    await tester.ensureVisible(missing);
    await tester.pumpAndSettle();
    await tester.tap(missing);
    expect(seeks.length, 1);
    final valid = find.ancestor(
        of: find.textContaining('측정 근거 보기'),
        matching: find.byType(TextButton));
    expect(tester.widget<TextButton>(valid).onPressed, isNotNull);
    await tester.ensureVisible(valid);
    await tester.pumpAndSettle();
    await tester.tap(valid);
    expect(seeks.last, const Duration(milliseconds: 1250));
    expect(tester.takeException(), isNull);
  });
}
