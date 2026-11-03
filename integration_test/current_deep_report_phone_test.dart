// Registered by the one-build coaching harness, selected by local bpt_demo mode.
// Existing HTTP bytes and video only: no inference, credentials, upload or records.
import 'dart:convert';
import 'dart:io';
import 'package:bpt/core/theme/app_theme.dart';
import 'package:bpt/features/workout/data/deep_analysis_service.dart';
import 'package:bpt/features/workout/data/deep_assessment_evidence.dart';
import 'package:bpt/features/workout/data/experimental_coaching_candidate.dart';
import 'package:bpt/features/workout/screens/deep_analysis_report_screen.dart';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

class _DenyTransport extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Local report test prohibits all Dart transport');
  }
}

void registerCurrentDeepReportTest({void Function(String)? onOutputCreated}) {
  testWidgets(
    'saved re-score HTTP bytes and original local video, no user writes',
    (tester) async {
      final docs = await getApplicationDocumentsDirectory();
      final output = Directory(
        '${docs.path}/current_phone_validation/output_${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true);
      onOutputCreated?.call(output.path.substring(docs.path.length + 1));
      File local(Object? raw) {
        if (raw is! String ||
            raw.isEmpty ||
            raw.startsWith('/') ||
            raw.split('/').contains('..')) {
          throw StateError(
            'Require explicit Documents-relative existing input',
          );
        }
        return File('${docs.path}/$raw');
      }

      final oldHttp = HttpOverrides.current;
      final deny = _DenyTransport();
      HttpOverrides.global = deny;
      SharedPreferences.setMockInitialValues({});
      VideoPlayerController? video;
      final seeks = <int>[];
      try {
        final config =
            jsonDecode(File('${docs.path}/bpt_demo.json').readAsStringSync())
                as Map;
        expect('${config['BPT_DEMO_AUTOPILOT'] ?? '0'}', '0');
        expect('${config['BPT_SET_RECORDING'] ?? '0'}', '0');
        expect('${config['BPT_VOICE_MUTE']}', '1');
        expect('${config['BPT_TERMINAL_EVIDENCE'] ?? '0'}', '0');
        final bindingFile = local(config['BPT_DEEP_REPORT_BINDING']);
        final binding = jsonDecode(bindingFile.readAsStringSync()) as Map;
        expect(binding['schema'], 'bpt.phone-saved-rescore-binding.v1');
        expect(binding['newInference'], isFalse);
        Future<List<int>> checked(String pathKey, String hashKey) async {
          final bytes = await local(binding[pathKey]).readAsBytes();
          expect(sha256.convert(bytes).toString(), binding[hashKey]);
          return bytes;
        }

        final responseBytes = await checked(
          'responseRelativePath',
          'responseSHA256',
        );
        final reportBytes = await checked('reportRelativePath', 'reportSHA256');
        await checked('originalReportRelativePath', 'originalReportSHA256');
        final videoFile = local(binding['videoRelativePath']);
        expect(
          (await sha256.bind(videoFile.openRead()).first).toString(),
          binding['videoSHA256'],
        );
        final response = (jsonDecode(utf8.decode(responseBytes)) as Map)
            .cast<String, dynamic>();
        expect(response.containsKey('localTestWrapper'), isFalse);
        final job = DeepAnalysisJob.fromJson(response);
        expect(job.status, 'done');
        final report = (job.result!['report'] as Map).cast<String, dynamic>();
        final expected = (jsonDecode(utf8.decode(reportBytes)) as Map)
            .cast<String, dynamic>();
        Map core(Map r) => Map.fromEntries(
              r.entries.where((e) => !{'runtime', 'bodyShape'}.contains(e.key)),
            );
        expect(core(report), core(expected));
        final typed = DeepAssessmentEvidence.parseReport(report)!;
        expect(typed.reps, hasLength(10));
        final metrics =
            typed.reps.values.expand((r) => r.metrics.values).toList();
        expect(metrics, hasLength(150));
        expect(metrics.every((m) => !m.postureAssessment.available), isTrue);
        final packetBytes = await checked(
          'nativeTransitionRelativePath',
          'nativeTransitionSHA256',
        );
        final packets = jsonDecode(utf8.decode(packetBytes)) as Map;
        expect(packets['synthetic'], isTrue);
        final events = packets['events'] as List;
        final inbox = ExperimentalCoachingCandidateInbox();
        final old = events[0]['payload'] as Map,
            clear = events[1]['payload'] as Map,
            next = events[2]['payload'] as Map;
        expect(inbox.accept(old, active: true), isTrue);
        expect(inbox.expire(clear), isTrue);
        expect(inbox.accept(next, active: true), isTrue);
        expect(inbox.accept(old, active: true), isFalse);
        expect(
          inbox.accept({
            ...old,
            'source': {
              ...old['source'] as Map,
              'epoch': 99,
              'source_index': 999,
            },
          }, active: true),
          isFalse,
        );
        expect(inbox.expire(clear), isFalse);
        video = VideoPlayerController.file(videoFile);
        await video.initialize().timeout(const Duration(seconds: 30));
        await video.setVolume(0);
        expect(video.value.duration.inMilliseconds, greaterThan(0));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: SafeArea(
                child: DeepAnalysisReport(
                  report: report,
                  video: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('저장된 분석 다시 보기 · 영상 기반 추정값'),
                      SizedBox(
                        height: 180,
                        child: AspectRatio(
                          aspectRatio: video.value.aspectRatio,
                          child: VideoPlayer(video),
                        ),
                      ),
                    ],
                  ),
                  onSeek: (time) {
                    seeks.add(time.inMilliseconds);
                    video!.seekTo(time);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final index = (report['reps'] as List).first['repIndex'];
        final title = find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data?.startsWith('$index회 ·') ?? false),
          ),
        );
        await tester.scrollUntilVisible(title, 200, maxScrolls: 60);
        // Device fullyLive uses the real frame clock. A duration passed to one
        // pump is not evidence that scrolling or expansion has completed.
        await Scrollable.ensureVisible(tester.element(title),
            alignment: .5, duration: const Duration(milliseconds: 250));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump();
        final tapRect = tester.getRect(title);
        await tester.tap(title);
        String visibleText() => tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join('\n');
        final expansionDeadline =
            DateTime.now().add(const Duration(seconds: 10));
        while (!visibleText().contains('3차원 영상 추정값') &&
            DateTime.now().isBefore(expansionDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final text = visibleText();
        File('${output.path}/expansion-attempt.json').writeAsStringSync(
            jsonEncode({
              'repIndex': index,
              'tapRect': {
                'left': tapRect.left,
                'top': tapRect.top,
                'width': tapRect.width,
                'height': tapRect.height
              },
              'tapCount': 1,
              'expandedEvidenceVisible': text.contains('3차원 영상 추정값'),
              'visibleText': text,
            }),
            flush: true);
        expect(text, contains('3차원 영상 추정값'));
        expect(text, contains('변화량 기준:'));
        expect(text, isNot(contains('NaN')));
        expect(tester.takeException(), isNull);
        await video.play();
        await Future<void>.delayed(const Duration(seconds: 2));
        await video.pause();
        expect(video.value.position.inMilliseconds, greaterThan(0));
        final timeline =
            (report['timeline'] as List).whereType<Map>().firstWhere(
                  (r) =>
                      r['t'] is num &&
                      (r['t'] as num).isFinite &&
                      (r['t'] as num) >= 0,
                );
        final timelineFinder = find
            .byWidgetPredicate((w) => w is ListTile && w.onTap != null)
            .first;
        await tester.ensureVisible(timelineFinder);
        await tester.tap(timelineFinder);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(seeks.last, ((timeline['t'] as num) * 1000).round());
        final positiveTimes = (report['timeline'] as List)
            .whereType<Map>()
            .map((r) => r['t'])
            .whereType<num>()
            .where((t) =>
                t.isFinite &&
                t > 0 &&
                t * 1000 < video!.value.duration.inMilliseconds)
            .toList();
        final targetMs = positiveTimes.isEmpty
            ? video.value.duration.inMilliseconds ~/ 2
            : (positiveTimes.first * 1000).round();
        expect(targetMs, greaterThan(0));
        tester
            .widget<DeepAnalysisReport>(find.byType(DeepAnalysisReport))
            .onSeek(Duration(milliseconds: targetMs));
        final seekDeadline = DateTime.now().add(const Duration(seconds: 8));
        while ((video.value.position.inMilliseconds - targetMs).abs() > 500 &&
            DateTime.now().isBefore(seekDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(video.value.hasError, isFalse);
        expect((video.value.position.inMilliseconds - targetMs).abs(),
            lessThanOrEqualTo(500));
        final achievedMs = video.value.position.inMilliseconds;
        expect(deny.attempts, 0);
        File('${output.path}/success.json').writeAsStringSync(
          jsonEncode({
            'scope': 'saved_rescore_existing_http_bytes_local_video_injection',
            'newInference': false,
            'remoteVideoURLTested': false,
            'credentialsUsed': false,
            'reportRepCount': typed.reps.length,
            'typedMetrics': metrics.length,
            'bindingSHA256':
                sha256.convert(bindingFile.readAsBytesSync()).toString(),
            'responseSHA256': binding['responseSHA256'],
            'reportSHA256': binding['reportSHA256'],
            'originalReportSHA256': binding['originalReportSHA256'],
            'videoSHA256': binding['videoSHA256'],
            'nativeVideoInitialized': true,
            'localPlaybackAdvanced': true,
            'tappedTimelineCallbackRequestedMs':
                ((timeline['t'] as num) * 1000).round(),
            'positiveSeekRequestedMs': targetMs,
            'positiveSeekAchievedMs': achievedMs,
            'seekToleranceMs': 500,
            'positiveSeekSource':
                positiveTimes.isEmpty ? 'duration_half' : 'saved_timeline',
            'nativeVideoHasError': video.value.hasError,
            'syntheticNativeTransitionInboxReplay': true,
            'retiredPacketsRejected': true,
            'networkAttempts': deny.attempts,
            'realPreferencesBackendUsed': false,
            'realRecordWrites': 0,
          }),
          flush: true,
        );
      } catch (e, st) {
        File(
          '${output.path}/failure.txt',
        ).writeAsStringSync('$e\n$st', flush: true);
        rethrow;
      } finally {
        try {
          try {
            await tester
                .pumpWidget(const SizedBox())
                .timeout(const Duration(seconds: 10));
          } finally {
            await video?.dispose().timeout(const Duration(seconds: 10));
          }
          File('${output.path}/cleanup-complete.json').writeAsStringSync(
              jsonEncode({
                'widgetDisposed': true,
                'playerDisposed': true,
                'inputsDeleted': false
              }),
              flush: true);
        } catch (error) {
          File('${output.path}/cleanup-failed.json').writeAsStringSync(
              jsonEncode({'errorType': error.runtimeType.toString()}),
              flush: true);
          rethrow;
        } finally {
          HttpOverrides.global = oldHttp;
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
