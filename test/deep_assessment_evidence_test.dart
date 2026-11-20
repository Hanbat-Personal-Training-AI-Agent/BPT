import 'dart:convert';
import 'dart:io';

import 'package:bpt/features/workout/data/deep_assessment_evidence.dart';
import 'package:bpt/features/workout/screens/deep_analysis_report_screen.dart';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sample() {
  Map<String, dynamic> metric(String key, String coordinate, String unit,
          {List<int> refs = const []}) =>
      {
        'key': key,
        'definition': 'Declared full-span measurement',
        'unit': unit,
        'coordinateType': coordinate,
        'referenceType': refs.isEmpty
            ? 'within_declared_rep'
            : 'first_up_to_three_reps_median',
        'referenceReps': refs,
        'measurement': {
          'assessment': 'available',
          'reasons': [],
          'minimumJointSupport': .8
        },
        'postureAssessment': {
          'assessment': 'withheld',
          'reasons': ['validated_posture_target_missing']
        },
      };
  final metrics = [
    metric('elbow', 'joint_interior_angle', 'deg'),
    metric('handPath', 'pelvis_relative_wrist_midpoint', 'm'),
    metric('romDropDeg', 'joint_interior_angle', 'deg', refs: [7]),
  ];
  return {
    'exerciseId': 'barbell-row',
    'fps': 30,
    'reps': <dynamic>[
      {
        'repIndex': 7,
        'startMs': 0,
        'endMs': 1000,
        'side': 'left',
        'confidence': .8,
        'comparison': 'agree',
        'primaryJoint': 'elbow',
        'anglesDeg': {
          'elbow': {'top': 150, 'bottom': 60}
        },
        'handPath': {'length': .3},
        'metricValidity': {for (final m in metrics) m['key']: m['measurement']},
      }
    ],
    'assessmentEvidence': {
      'schema': 'bpt.deep-assessment-evidence.v1',
      'coordinateSystem': 'h36m17_gravity_aligned_world_m',
      'referenceType': 'estimated_geometry_not_ground_truth',
      'exerciseId': 'barbell-row',
      'fps': 30,
      'sourceTimeBasis': 'video_ms',
      'reps': <dynamic>[
        {
          'repIndex': 7,
          'startMs': 0,
          'endMs': 1000,
          'side': 'left',
          'metrics': metrics,
          'nativeComparison': {
            'assessment': 'withheld',
            'reasons': ['native_metric_contract_missing'],
            'comparableKeys': [],
            'unassessedKeys': ['symmetry']
          },
        }
      ],
    },
  };
}

Map evidence(Map r) => r['assessmentEvidence'] as Map;
Map repEvidence(Map r) => (evidence(r)['reps'] as List).first as Map;
Map metric(Map r, String key) => (repEvidence(r)['metrics'] as List)
    .cast<Map>()
    .firstWhere((m) => m['key'] == key);

Future<String> render(
    WidgetTester tester, Map<String, dynamic> report, int index) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: DeepAnalysisReport(
    report: report,
    video: const SizedBox(height: 10),
    onSeek: (_) {},
  ))));
  final title = find.descendant(
      of: find.byType(ExpansionTile),
      matching: find.byWidgetPredicate(
          (w) => w is Text && (w.data?.startsWith('$index회 ·') ?? false)));
  await tester.scrollUntilVisible(title, 200, maxScrolls: 60);
  await tester.tap(title);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join('\n');
}

void main() {
  test('optional legacy, unknown version and malformed report fail closed', () {
    expect(DeepAssessmentEvidence.parseReport({}), isNull);
    for (final bad in [
      null,
      [],
      'bad',
      {'schema': 'future'},
      {'schema': 'bpt.deep-assessment-evidence.v1'}
    ]) {
      final r = sample()..['assessmentEvidence'] = bad;
      expect(DeepAssessmentEvidence.parseReport(r), isNull);
    }
    final r = sample()..['reps'] = 'bad';
    expect(DeepAssessmentEvidence.parseReport(r), isNull);
  });
  test('binding rejects mismatched exercise, clock, fps and rep span', () {
    for (final change in <void Function(Map)>[
      (r) => evidence(r)['exerciseId'] = 'squat',
      (r) => evidence(r)['fps'] = double.nan,
      (r) => evidence(r)['fps'] = 60,
      (r) => evidence(r)['sourceTimeBasis'] = 'model_frames',
    ]) {
      final r = sample();
      change(r);
      expect(DeepAssessmentEvidence.parseReport(r), isNull);
    }
    for (final field in ['startMs', 'endMs', 'side']) {
      final r = sample();
      repEvidence(r)[field] = field == 'side' ? 'right' : 50;
      expect(DeepAssessmentEvidence.parseReport(r)!.reps, isEmpty);
    }
  });
  test('fractional video milliseconds bind exactly without rounding', () {
    final r = sample();
    (r['reps'] as List).first['endMs'] = 2733.3333333333335;
    repEvidence(r)['endMs'] = 2733.3333333333335;
    expect(DeepAssessmentEvidence.parseReport(r)!.reps.keys, contains(7));
    repEvidence(r)['endMs'] = 2733;
    expect(DeepAssessmentEvidence.parseReport(r)!.reps, isEmpty);
  });
  test('malformed metric never discards unrelated observations', () {
    for (final change in <void Function(Map)>[
      (m) => m['unit'] = 'm',
      (m) => m['coordinateType'] = 'world_pelvis_vertical',
      (m) => m['measurement'] = {
            'assessment': 'available',
            'reasons': [],
            'minimumJointSupport': null
          },
      (m) => m['measurement'] = {
            'assessment': 'available',
            'reasons': ['low_joint_support']
          },
      (m) =>
          m['postureAssessment'] = {'assessment': 'available', 'reasons': []},
    ]) {
      final r = sample();
      change(metric(r, 'elbow'));
      final parsed = DeepAssessmentEvidence.parseReport(r)!.reps[7]!;
      expect(parsed.metrics.containsKey('elbow'), isFalse);
      expect(parsed.metrics.containsKey('handPath'), isTrue);
    }
  });
  test(
      'duplicates, stale baseline and conflicting owning support are rejected locally',
      () {
    final duplicate = sample();
    (repEvidence(duplicate)['metrics'] as List)
        .add({'key': 'elbow', 'unit': 'invalid'});
    expect(DeepAssessmentEvidence.parseReport(duplicate)!.reps[7]!.metrics.keys,
        isNot(contains('elbow')));
    final stale = sample();
    metric(stale, 'romDropDeg')['referenceReps'] = [1];
    expect(DeepAssessmentEvidence.parseReport(stale)!.reps[7]!.metrics.keys,
        containsAll(['elbow', 'handPath']));
    expect(DeepAssessmentEvidence.parseReport(stale)!.reps[7]!.metrics.keys,
        isNot(contains('romDropDeg')));
    final conflict = sample();
    (conflict['reps'] as List).first['metricValidity']['elbow'] = {
      'assessment': 'withheld',
      'reasons': ['low_joint_support']
    };
    expect(DeepAssessmentEvidence.parseReport(conflict)!.reps[7]!.metrics.keys,
        isNot(contains('elbow')));
    final repeated = sample();
    (evidence(repeated)['reps'] as List).add(<String, dynamic>{
      ...repEvidence(repeated).cast<String, dynamic>(),
      'startMs': -1
    });
    expect(DeepAssessmentEvidence.parseReport(repeated)!.reps, isEmpty);
  });
  testWidgets(
      'partial support visible, exact baseline and no false native agreement',
      (tester) async {
    final r = sample();
    final withheld = {
      'assessment': 'withheld',
      'reasons': ['low_joint_support'],
      'minimumJointSupport': .2
    };
    metric(r, 'handPath')['measurement'] = withheld;
    (r['reps'] as List).first['metricValidity']['handPath'] = withheld;
    final text = await render(tester, r, 7);
    expect(text, contains('팔꿈치 · 위 150° / 아래 60° (영상 추정값)'));
    expect(text, contains('0.3m'));
    expect(text, contains('일부 관절·추적 근거가 부족'));
    expect(text, contains('변화량 기준: 7회의 중앙값'));
    expect(text, contains('일치 여부를 판정하지 않았어'));
    expect(text, isNot(contains('비교한 항목은 기기와 같아')));
  });
  testWidgets(
      'malformed evidence and falsely available comparison do not assert equivalence',
      (tester) async {
    final r = sample();
    repEvidence(r)['nativeComparison'] = {
      'assessment': 'available',
      'reasons': [],
      'comparableKeys': ['symmetry'],
      'unassessedKeys': []
    };
    var text = await render(tester, r, 7);
    expect(text, contains('같은 기준으로 비교했는지 확인할 수 없어'));
    await tester.pumpWidget(const SizedBox());
    r['assessmentEvidence'] = 'malformed';
    text = await render(tester, r, 7);
    expect(text, contains('측정 정의와 비교 기준을 확인할 수 없어'));
    expect(text, contains('팔꿈치 · 위 150° / 아래 60° (측정 근거 미확인)'));
  });

  final realPath = Platform.environment['BPT_EXPECTED_CURRENT_REPORT_FILE'];
  testWidgets(
      'hash-bound saved worker re-score replays through actual report widget',
      (tester) async {
    final bytes = File(realPath!).readAsBytesSync();
    expect(sha256.convert(bytes).toString(),
        Platform.environment['BPT_EXPECTED_CURRENT_REPORT_SHA256']);
    final report =
        (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
    final parsed = DeepAssessmentEvidence.parseReport(report)!;
    expect(parsed.reps, hasLength(10));
    final allMetrics =
        parsed.reps.values.expand((r) => r.metrics.values).toList();
    expect(allMetrics, hasLength(150));
    expect(allMetrics.where((m) => m.measurement.available), hasLength(141));
    expect(allMetrics.every((m) => !m.postureAssessment.available), isTrue);
    final text = await render(
        tester, report, (report['reps'] as List).first['repIndex'] as int);
    expect(text, contains('3차원 영상 추정값'));
    expect(text, contains('위팔·몸통 사이 각도(어깨 대리지표)'));
    expect(text, contains('변화량 기준:'));
    expect(text, isNot(contains('비교한 항목은 기기와 같아')));
    expect(text, isNot(contains('NaN')));
  }, skip: realPath == null);
}
