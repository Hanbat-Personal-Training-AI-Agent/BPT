// Host-only consumer of the bytes actually returned by the owned LOCAL HTTP API.
import 'dart:convert';
import 'dart:io';
import 'package:bpt/core/theme/app_theme.dart';
import 'package:bpt/features/workout/data/deep_assessment_evidence.dart';
import 'package:bpt/features/workout/data/deep_analysis_service.dart';
import 'package:bpt/features/workout/screens/deep_analysis_report_screen.dart';
// Already lock-pinned transitive package, no dependency resolution/change.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DenyNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Host parser/widget preflight must not request any URL');
  }
}

Map<String, dynamic> _core(Map<String, dynamic> report) => Map.fromEntries(
    report.entries.where((e) => !{'runtime', 'bodyShape'}.contains(e.key)));
void main() {
  testWidgets('real local API response production parser and report widget',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final responsePath = Platform.environment['BPT_LOCAL_API_RESPONSE_FILE'];
    final responseSHA = Platform.environment['BPT_LOCAL_API_RESPONSE_SHA256'];
    final workerPath = Platform.environment['BPT_ORIGINAL_WORKER_FILE'];
    final outPath = Platform.environment['BPT_LOCAL_WIDGET_PROOF_FILE'];
    expect(
        [responsePath, responseSHA, workerPath, outPath]
            .every((x) => x != null && x.isNotEmpty),
        isTrue,
        reason: 'Explicit private artifacts required; no synthetic fallback');
    final bytes = File(responsePath!).readAsBytesSync();
    expect(sha256.convert(bytes).toString(), responseSHA);
    final originalBytes = File(workerPath!).readAsBytesSync();
    expect(sha256.convert(originalBytes).toString(),
        'f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa');
    final envelope =
        (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
    expect(envelope.containsKey('localTestWrapper'), isFalse);
    final job = DeepAnalysisJob.fromJson(envelope);
    expect(job.status, 'done');
    expect(job.progress, 100);
    final report = (job.result!['report'] as Map).cast<String, dynamic>();
    final original =
        (jsonDecode(utf8.decode(originalBytes)) as Map).cast<String, dynamic>();
    final expectedPath =
        Platform.environment['BPT_EXPECTED_CURRENT_REPORT_FILE'];
    final expectedSha =
        Platform.environment['BPT_EXPECTED_CURRENT_REPORT_SHA256'];
    expect(expectedPath == null, expectedSha == null,
        reason: 'Current re-score path and hash must be supplied together');
    final expected = expectedPath == null
        ? original
        : () {
            final expectedBytes = File(expectedPath).readAsBytesSync();
            expect(sha256.convert(expectedBytes).toString(), expectedSha);
            return (jsonDecode(utf8.decode(expectedBytes)) as Map)
                .cast<String, dynamic>();
          }();
    expect(_core(report), equals(_core(expected)),
        reason:
            'HTTP must preserve the hash-bound report except runtime/bodyShape');
    if (expectedPath != null) {
      final evidence = DeepAssessmentEvidence.parseReport(report);
      expect(evidence, isNotNull);
      expect(evidence!.reps.length, (report['reps'] as List).length);
      expect(
          evidence.reps.values.expand((r) => r.metrics.values), hasLength(150));
      expect(
          evidence.reps.values
              .expand((r) => r.metrics.values)
              .every((m) => !m.postureAssessment.available),
          isTrue);
    }
    expect(report['bodyShape'], {'source': 'gvhmr_fallback'});
    expect(report['runtime'], isA<Map>());
    final reps = report['reps'] as List;
    expect(reps, hasLength(10));
    final deny = _DenyNetwork();
    final old = HttpOverrides.current;
    HttpOverrides.global = deny;
    try {
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
              body: DeepAnalysisReport(
                  report: report,
                  video: const SizedBox(height: 80),
                  onSeek: (_) => fail('Seek not part of host test')))));
      await tester.pump();
      final index = (reps.first as Map)['repIndex'];
      final title = find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.byWidgetPredicate(
              (w) => w is Text && (w.data?.startsWith('$index회 ·') ?? false)));
      await tester.scrollUntilVisible(title, 200, maxScrolls: 60);
      expect(title, findsOneWidget);
      await tester.tap(title);
      await tester.pumpAndSettle();
      final visible = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join('\n');
      if (expectedPath != null) {
        expect(visible, contains('3차원 영상 추정값'));
        expect(visible, contains('위팔·몸통 사이 각도(어깨 대리지표)'));
        expect(visible, contains('변화량 기준:'));
        expect(visible, isNot(contains('비교한 항목은 기기와 같아')));
      }
      expect(visible.contains('null°') || visible.contains('NaN'), isFalse);
      expect(tester.takeException(), isNull);
      expect(deny.attempts, 0);
      File(outPath!).writeAsStringSync(
          jsonEncode({
            'status':
                'PASS_HOST_PRODUCTION_PARSER_WIDGET_GENUINE_LOCAL_HTTP_RESPONSE',
            'responseSHA256': responseSHA,
            'originalWorkerSHA256': sha256.convert(originalBytes).toString(),
            'manuallyBuiltEnvelope': false,
            'currentRescoredReportSHA256': expectedSha,
            'typedAssessmentEvidenceVisible': expectedPath != null,
            'reportCoreUnchangedExceptRuntimeBodyShape': true,
            'reportRepCount': reps.length,
            'timelineCount': (report['timeline'] as List).length,
            'firstRepExpanded': true,
            'noNullDegreeOrNaNVisible': true,
            'DartNetworkAttempts': deny.attempts,
            'videoPlaceholder': true,
            'headlessViewport': '390x844',
            'overflowExceptions': false,
            'phoneVideoAuthSpringTLSClientUploadInferenceTested': false,
            'localApiHarnessAndPlaceholderVideoOnly': true
          }),
          flush: true);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox());
      } finally {
        HttpOverrides.global = old;
      }
    }
  });
}
