// Opt-in numeric capture only. Never call main/DemoAutopilot or save user state.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'current_deep_report_phone_test.dart' as report_mode;
import 'package:bpt/features/workout/data/experimental_coaching_candidate.dart';
import 'package:bpt/features/workout/widgets/experimental_coaching_candidate_banner.dart';

class _NoHttp extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Terminal capture forbids transport');
  }
}

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final modeDocs = await getApplicationDocumentsDirectory();
  final modeConfigBytes =
      File('${modeDocs.path}/bpt_demo.json').readAsBytesSync();
  final modeConfig = jsonDecode(utf8.decode(modeConfigBytes)) as Map;
  final mode = '${modeConfig['BPT_PHONE_TEST_MODE'] ?? 'capture'}';
  final attempt = '${modeConfig['BPT_TERMINAL_TEST_ATTEMPT'] ?? ''}';
  if (!RegExp(r'^terminal_[A-Za-z0-9_-]+$').hasMatch(attempt)) {
    throw StateError('Runner receipt requires a unique host-bound attempt');
  }
  String? outputRelativePath;
  void outputCreated(String path) {
    outputRelativePath = path;
  }

  // The SDK completes this future in tearDownAll, after per-test teardown.
  // Observe it; never complete it ourselves or infer success from inner files.
  unawaited(binding.allTestsPassed.future.then((passed) {
    final directory = Directory('${modeDocs.path}/current_phone_runner')
      ..createSync(recursive: true);
    final receipt = File('${directory.path}/$attempt.json');
    if (receipt.existsSync()) throw StateError('Runner receipt already exists');
    receipt.writeAsStringSync(
        jsonEncode({
          'schema': 'bpt.phone-integration-runner-completion.v1',
          'hostAttemptId': attempt,
          'mode': mode,
          'configurationSHA256': sha256.convert(modeConfigBytes).toString(),
          'outputRelativePath': outputRelativePath,
          'sdkAllTestsPassed': passed,
          'testCount': binding.results.length,
          'testNames': binding.results.keys.toList(),
          'completedAt': DateTime.now().toUtc().toIso8601String(),
          'source':
              'IntegrationTestWidgetsFlutterBinding.allTestsPassed.future',
        }),
        flush: true);
  }));
  if (mode == 'report') {
    report_mode.registerCurrentDeepReportTest(onOutputCreated: outputCreated);
    return;
  }
  testWidgets(
    'explicit core3 engineering candidates without user writes',
    (tester) async {
      final docs = await getApplicationDocumentsDirectory();
      final output = Directory(
        '${docs.path}/coaching_candidate_validation/${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true);
      outputCreated(output.path.substring(modeDocs.path.length + 1));
      final stages = <Map<String, dynamic>>[];
      void stage(String name, [Map<String, dynamic> fields = const {}]) {
        stages.add({
          'stage': name,
          'at': DateTime.now().toUtc().toIso8601String(),
          ...fields,
        });
        File('${output.path}/progress.json').writeAsStringSync(
          jsonEncode({
            'stages': stages,
            'stage': name,
            'at': DateTime.now().toUtc().toIso8601String(),
            ...fields,
          }),
          flush: true,
        );
      }

      final oldHttp = HttpOverrides.current;
      final noHttp = _NoHttp();
      HttpOverrides.global = noHttp;
      SharedPreferences.setMockInitialValues({});
      var flutterErrors = 0;
      final oldError = FlutterError.onError;
      FlutterError.onError = (details) {
        flutterErrors++;
        File('${output.path}/private-errors.txt').writeAsStringSync(
          '$details\n${details.stack}\n',
          mode: FileMode.append,
          flush: true,
        );
        oldError?.call(details);
      };
      MethodChannel? channel;
      final ready = Completer<void>();
      final setEnd = Completer<Map>();
      final observed = <Map<String, dynamic>>[];
      final candidateInbox = ExperimentalCoachingCandidateInbox();
      final candidateUi = ValueNotifier<ExperimentalCoachingCandidate?>(null);
      final proposals = <Map<String, dynamic>>[],
          clears = <Map<String, dynamic>>[];
      final syntheticPresented = Completer<Map<String, dynamic>>(),
          syntheticCleared = Completer<Map<String, dynamic>>();
      try {
        final config =
            jsonDecode(File('${docs.path}/bpt_demo.json').readAsStringSync())
                as Map;
        final terminalEnabled =
            '${config['BPT_PHONE_TEST_MODE'] ?? 'capture'}' != 'nonterminal';
        expect(
            '${config['BPT_TERMINAL_EVIDENCE']}', terminalEnabled ? '1' : '0');
        for (final key in [
          'BPT_EXPERIMENTAL_COACHING',
          'BPT_EXPERIMENTAL_CRITERIA_CANDIDATE',
          'BPT_TERMINAL_EOF_FLUSH',
        ]) {
          expect(
            '${config[key]}',
            '1',
            reason: 'Explicit host-owned opt-in required',
          );
        }
        expect('${config['BPT_VOICE_MUTE']}', '1');
        expect('${config['BPT_COACHING_CANDIDATE_TEST_FIXTURE']}', '1');
        final recording =
            '${config['BPT_TERMINAL_TEST_RECORDING'] ?? '0'}' == '1';
        expect('${config['BPT_SET_RECORDING']}', recording ? '1' : '0');
        expect('${config['BPT_CAMERA_VIDEO_LOOPS']}', '1');
        expect('${config['BPT_DEMO_AUTOPILOT'] ?? '0'}', '0');
        final clip = '${config['BPT_CAMERA_VIDEO'] ?? ''}';
        expect(
          clip.isNotEmpty &&
              !clip.contains(',') &&
              !clip.startsWith('/') &&
              !clip.split('/').contains('..'),
          isTrue,
        );
        expect(File('${docs.path}/$clip').existsSync(), isTrue);
        int? sourceDurationMs;
        if (recording) {
          final sourcePlayer = VideoPlayerController.file(
            File('${docs.path}/$clip'),
          );
          try {
            await sourcePlayer.initialize().timeout(
                  const Duration(seconds: 20),
                );
            sourceDurationMs = sourcePlayer.value.duration.inMilliseconds;
            expect(sourceDurationMs, greaterThan(0));
          } finally {
            await sourcePlayer.dispose();
          }
        }
        final exercise = '${config['BPT_TERMINAL_TEST_EXERCISE'] ?? ''}';
        expect(['squat', 'pushup', 'barbell-row'], contains(exercise));
        expect(
          recording,
          isFalse,
          reason: 'This candidate test never records a new video',
        );
        if (recording) {
          final videos = Directory('${docs.path}/workout_videos');
          final count = videos.existsSync()
              ? videos
                  .listSync()
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.mp4'))
                  .length
              : 0;
          expect(
            count,
            lessThan(20),
            reason: 'Never permit recorder pruning of an existing video',
          );
        }
        final namespace = '${config['BPT_TERMINAL_NAMESPACE'] ?? ''}';
        expect(namespace.length, lessThanOrEqualTo(64));
        expect(
          RegExp(r'^coaching-candidate-[A-Za-z0-9_-]+$').hasMatch(namespace),
          isTrue,
        );
        final logDir = Directory('${docs.path}/video_runs/$namespace');
        expect('${config['BPT_TERMINAL_CANDIDATE'] ?? '0'}', '0');
        expect(
          '${config['BPT_COACHING_CANDIDATE_VARIANT']}',
          {
            'squat': 'barbell_back_squat',
            'pushup': 'floor',
            'barbell-row': 'strict_bent_over',
          }[exercise],
        );
        for (final key in [
          'BPT_COACHING_CANDIDATE_EXPERIMENT_ID',
          'BPT_COACHING_CANDIDATE_SOURCE',
          'BPT_COACHING_CANDIDATE_DECLARED_AT',
        ]) {
          expect('${config[key] ?? ''}'.isNotEmpty, isTrue);
        }
        final runTag = '${config['BPT_RUN_TAG'] ?? ''}';
        if (!terminalEnabled) {
          expect(RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(runTag), isTrue);
          expect('${config['BPT_NORMAL_RUN_LOG_PRELAUNCH_ABSENT']}', '1');
        }
        final ownedNormalLogName = 'run_$runTag.jsonl';
        final ownedNormalLog =
            File('${docs.path}/video_runs/$ownedNormalLogName');
        Map<String, int> originalRootFiles() => {
              for (final file in Directory(
                '${docs.path}/video_runs',
              ).listSync().whereType<File>().where((f) =>
                  terminalEnabled ||
                  f.path.split('/').last != ownedNormalLogName))
                file.path.split('/').last: file.lengthSync(),
            };
        final originalFilesBefore = originalRootFiles();
        final attemptId = '${config['BPT_TERMINAL_TEST_ATTEMPT'] ?? ''}';
        expect(
          RegExp(r'^terminal_[A-Za-z0-9_-]+$').hasMatch(attemptId),
          isTrue,
        );
        final priorNames = (jsonDecode(
          config['BPT_TERMINAL_TEST_PRIOR_TERMINAL_NAMES'] as String,
        ) as List)
            .cast<String>();
        expect(priorNames.toSet().length, priorNames.length);
        for (final name in priorNames) {
          expect(
            name.startsWith('terminal_') &&
                name.endsWith('.jsonl') &&
                !name.contains('/'),
            isTrue,
          );
        }
        // NativePoseRegistration opens this process's header before Dart main.
        // Ownership therefore comes from the host's bound prelaunch snapshot.
        final before = priorNames.map((name) => '${logDir.path}/$name').toSet();
        expect(
          before.length,
          lessThan(3),
          reason:
              'Native cap applies to prior files, not this already-created header',
        );
        for (final name in before) {
          expect(File(name).existsSync(), isTrue);
        }
        expect(
          '${config['BPT_TERMINAL_TEST_ORIGINAL_DEMO_SHA256']}',
          matches(RegExp(r'^[0-9a-f]{64}$')),
        );
        expect(
          '${config['BPT_TERMINAL_TEST_PRIOR_INVENTORY_SHA256']}',
          matches(RegExp(r'^[0-9a-f]{64}$')),
        );
        stage('preflight_pass', {
          'terminalFilesBefore': before.length,
          'hostAttemptId': attemptId,
          'originalDemoSHA256':
              config['BPT_TERMINAL_TEST_ORIGINAL_DEMO_SHA256'],
          'priorInventorySHA256':
              config['BPT_TERMINAL_TEST_PRIOR_INVENTORY_SHA256'],
          'exercise': exercise,
          'recording': recording,
          'sourceDurationMs': sourceDurationMs,
        });
        await tester
            .pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: UiKitView(
                          viewType: 'bpt/native_pose_camera',
                          creationParams: {'exerciseId': exercise},
                          creationParamsCodec: const StandardMessageCodec(),
                          onPlatformViewCreated: (id) async {
                            channel = MethodChannel(
                              'bpt/native_pose_camera/$id',
                            );
                            channel!.setMethodCallHandler((call) async {
                              if (call.method == 'onSetEnd' &&
                                  !setEnd.isCompleted) {
                                setEnd.complete(call.arguments as Map);
                              }
                              if (call.method == 'onPoseUpdate') {
                                final args = call.arguments as Map;
                                observed.add({
                                  'rep': args['rep'],
                                  'status': args['status'],
                                });
                              }
                              if (call.method ==
                                  'onExperimentalCoachingCandidate') {
                                final packet = Map<String, dynamic>.from(
                                  call.arguments as Map,
                                );
                                final accepted = candidateInbox.accept(
                                  packet,
                                  active: true,
                                );
                                candidateUi.value = candidateInbox.current;
                                proposals.add({
                                  ...packet,
                                  'presented': accepted,
                                });
                                if (accepted &&
                                    (packet['context'] as Map)['source_kind'] ==
                                        'synthetic_fixture' &&
                                    !syntheticPresented.isCompleted) {
                                  syntheticPresented.complete(packet);
                                }
                                return {
                                  'presented': accepted,
                                  'proposalId': packet['proposalId'],
                                  'tts': false,
                                };
                              }
                              if (call.method ==
                                  'onExperimentalCoachingCandidateClear') {
                                final packet = Map<String, dynamic>.from(
                                  call.arguments as Map,
                                );
                                final cleared = candidateInbox.expire(packet);
                                candidateUi.value = candidateInbox.current;
                                clears.add({...packet, 'cleared': cleared});
                                if (cleared && !syntheticCleared.isCompleted) {
                                  syntheticCleared.complete(packet);
                                }
                                return {'cleared': cleared, 'tts': false};
                              }
                              // Deliberately no speech response, account or result persistence.
                              return null;
                            });
                            await channel!.invokeMethod('setVoiceMuted', {
                              'muted': true,
                            });
                            ready.complete();
                          },
                        ),
                      ),
                      ValueListenableBuilder<ExperimentalCoachingCandidate?>(
                        valueListenable: candidateUi,
                        builder: (context, candidate, child) =>
                            candidate == null
                                ? const SizedBox()
                                : Positioned(
                                    top: 80,
                                    left: 16,
                                    right: 16,
                                    child: ExperimentalCoachingCandidateBanner(
                                      candidate: candidate,
                                      isKo: true,
                                    ),
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .timeout(const Duration(seconds: 15));
        await ready.future.timeout(const Duration(seconds: 20));
        stage('production_native_view_started');
        List<Map> normalEOFRows = [];
        if (!terminalEnabled) {
          final eofDeadline = DateTime.now().add(const Duration(minutes: 3));
          while (DateTime.now().isBefore(eofDeadline)) {
            try {
              normalEOFRows = ownedNormalLog
                  .readAsLinesSync()
                  .where((line) => line.isNotEmpty)
                  .map((line) => jsonDecode(line) as Map)
                  .toList();
            } catch (_) {
              normalEOFRows = [];
            }
            if (normalEOFRows.any((r) => r['type'] == 'video_end') &&
                normalEOFRows.any((r) => r['type'] == 'session_end')) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          expect(normalEOFRows.where((r) => r['type'] == 'video_end'),
              hasLength(1));
          expect(normalEOFRows.where((r) => r['type'] == 'session_end'),
              hasLength(1));
          // setup starts set 1. The actual EOF, not early positive counters,
          // authorizes the one explicit endSet in nonterminal mode.
          await channel!.invokeMethod('endSet', {'setIndex': 1});
        }
        final actualSetEnd =
            await setEnd.future.timeout(const Duration(minutes: 3));
        File('${output.path}/native-set-end.json').writeAsStringSync(
          jsonEncode({
            'scope': 'actual_native_onSetEnd_before_test_verdict',
            'hostAttemptId': attemptId,
            'exerciseId': exercise,
            'sourceDurationMs': sourceDurationMs,
            'recording': recording,
            'actualSetEnd': actualSetEnd,
          }),
          flush: true,
        );
        stage('actual_native_set_end_received');
        if (!terminalEnabled) {
          final diagnostic = Map<String, dynamic>.from(await channel!
                  .invokeMethod('getExperimentalCoachingCandidateDiagnostics')
              as Map);
          expect(diagnostic['schema'],
              'bpt.coaching-candidate-live-diagnostics.v1');
          expect(diagnostic['testFixture'], isTrue);
          expect(diagnostic['enabled'], isTrue);
          expect(diagnostic['terminalEvidenceEnabled'], isFalse);
          expect(diagnostic['processedFrames'], greaterThan(0));
          expect(diagnostic['mappedFrames'], greaterThan(0));
          expect(diagnostic['knownCandidateDecisions'], greaterThan(0));
          expect(diagnostic['sourceSessionActive'], isFalse);
          final source = diagnostic['lastSource'] as Map;
          expect(source['source_index'], isA<int>());
          expect(source['source_pts'], isA<num>());
          expect((source['source_pts'] as num).isFinite, isTrue);
          expect(source['time_basis'], 'sample_pts_seconds');
          final terminalNamesAfter = logDir.existsSync()
              ? logDir
                  .listSync()
                  .whereType<File>()
                  .where((f) =>
                      f.path.split('/').last.startsWith('terminal_') &&
                      f.path.endsWith('.jsonl'))
                  .map((f) => f.path)
                  .toSet()
              : <String>{};
          expect(terminalNamesAfter, before);
          expect(originalRootFiles(), originalFilesBefore);
          expect(noHttp.attempts, 0);
          expect(flutterErrors, 0);
          expect(tester.takeException(), isNull);
          File('${output.path}/success.json').writeAsStringSync(
              jsonEncode({
                'scope':
                    'actual_video_in_memory_processor_terminal_disabled_normal_video_log_enabled',
                'diagnostics': diagnostic,
                'poseUpdateEvents': observed.length,
                'terminalFilesUnchanged': true,
                'normalLogFile': ownedNormalLogName,
                'videoEndEvents':
                    normalEOFRows.where((r) => r['type'] == 'video_end').length,
                'sessionEndEvents': normalEOFRows
                    .where((r) => r['type'] == 'session_end')
                    .length,
                'explicitEndSetAfterEOF': true,
                'DartNetworkAttempts': noHttp.attempts,
                'newRecording': false,
                'realRecordWrites': 0,
                'realPreferencesBackendUsed': false,
                'syntheticInput': false,
                'accuracyClaim': false,
              }),
              flush: true);
          stage('nonterminal_in_memory_assertions_passed');
          return;
        }

        File? fresh;
        List<Map> rows = [];
        final until = DateTime.now().add(const Duration(seconds: 15));
        while (DateTime.now().isBefore(until)) {
          final files = logDir
              .listSync()
              .whereType<File>()
              .where(
                (f) =>
                    f.path.split('/').last.startsWith('terminal_') &&
                    f.path.endsWith('.jsonl') &&
                    !before.contains(f.path),
              )
              .toList();
          expect(files.length, lessThanOrEqualTo(1));
          if (files.length == 1) {
            fresh = files.single;
            try {
              rows = fresh
                  .readAsLinesSync()
                  .where((s) => s.isNotEmpty)
                  .map((s) => jsonDecode(s) as Map)
                  .toList();
            } catch (_) {
              rows = [];
            }
            if (rows.isNotEmpty && rows.last['type'] == 'terminal_end') break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        final pendingTestException = tester.takeException();
        File('${output.path}/operational-snapshot.json').writeAsStringSync(
          jsonEncode({
            'exerciseId': exercise,
            'recording': recording,
            'sourceDurationMs': sourceDurationMs,
            'terminalFileName': fresh?.path.split('/').last,
            'rows': rows.length,
            'footer': rows.isEmpty ? null : rows.last,
            'DartNetworkAttempts': noHttp.attempts,
            'flutterErrors': flutterErrors,
            'pendingTestExceptionType':
                pendingTestException?.runtimeType.toString(),
            'poseUpdateEvents': observed.length,
          }),
          flush: true,
        );
        stage('operational_output_preserved');
        expect(fresh, isNotNull);
        expect(rows.first['type'], 'terminal_header');
        expect(rows.last['type'], 'terminal_end');
        expect(rows.last['flush_complete'], isTrue);
        expect(rows.last['incomplete'], isFalse);
        expect(rows.where((r) => r['type'] == 'terminal_start'), hasLength(1));
        expect(rows.where((r) => r['type'] == 'terminal_end'), hasLength(1));
        expect(rows.where((r) => r['type'] == 'terminal_frame'), isNotEmpty);
        for (var i = 0; i < rows.length; i++) {
          expect(rows[i]['sequence'], i);
          expect(rows[i]['schema'], 'bpt.terminal-evidence.v1');
        }
        final candidateFrames =
            rows.where((row) => row['type'] == 'terminal_frame').toList();
        var knownCandidateDecisions = 0;
        var stoppedGenerationFrames = 0, flushWithoutCandidate = 0;
        final candidateCounts = <String, Map<String, int>>{};
        for (final frame in candidateFrames) {
          expect(frame.containsKey('coaching_candidate_error'), isFalse);
          final candidate = frame['coaching_candidate'];
          if (candidate == null) {
            final stopped =
                frame['coaching_candidate_status'] == 'stopped_generation';
            final flushed = frame['flush_tail'] == true;
            expect(
              stopped || flushed,
              isTrue,
              reason:
                  'Missing summary needs an explicit stopped generation or flush boundary',
            );
            if (stopped) stoppedGenerationFrames++;
            if (flushed) flushWithoutCandidate++;
            continue;
          }
          expect(candidate, isA<Map>());
          expect(
            frame['coaching_candidate_status'],
            isNot('stopped_generation'),
          );
          expect(candidate['schema'], 'bpt.core3-candidate-frame.v1');
          expect(
            candidate['authority'],
            'engineering_candidate_not_validated_form',
          );
          expect(candidate['delivered'], isFalse);
          final candidateSource = candidate['source'] as Map;
          for (final key in [
            'epoch',
            'frame',
            'source_index',
            'source_pts',
            'source_time_value',
            'source_time_scale',
            'time_basis',
          ]) {
            expect(candidateSource[key], frame[key]);
          }
          expect(
            candidate['variant'],
            '${config['BPT_COACHING_CANDIDATE_VARIANT']}',
          );
          for (final rule in candidate['rules'] as List) {
            final value = rule as Map;
            final id = value['id'] as String, state = value['state'] as String;
            expect([
              'positive_evidence',
              'negative_evidence',
              'unknown',
              'not_applicable',
            ], contains(state));
            final byState = candidateCounts.putIfAbsent(id, () => {});
            byState[state] = (byState[state] ?? 0) + 1;
            if (state == 'positive_evidence' || state == 'negative_evidence') {
              knownCandidateDecisions++;
            }
            if (frame['flush_tail'] == true) {
              expect(['unknown', 'not_applicable'], contains(state));
            }
          }
        }
        expect(
          knownCandidateDecisions,
          greaterThan(0),
          reason:
              'At least one supported configured candidate predicate must execute; silence is not a pass',
        );
        expect(
          originalRootFiles(),
          originalFilesBefore,
          reason: 'All original root video_run files must remain untouched',
        );
        File('${output.path}/candidate-counts.json').writeAsStringSync(
          jsonEncode({
            'namespace': namespace,
            'frames': candidateFrames.length,
            'knownCandidateDecisions': knownCandidateDecisions,
            'stoppedGenerationFrames': stoppedGenerationFrames,
            'flushWithoutCandidate': flushWithoutCandidate,
            'counts': candidateCounts,
            'originalRootFileSizesUnchanged': true,
          }),
          flush: true,
        );
        final terminalBytes = fresh!.readAsBytesSync();
        final compressed = File('${output.path}/terminal-evidence.jsonl.gz');
        compressed.writeAsBytesSync(gzip.encode(terminalBytes), flush: true);
        File('${output.path}/terminal-transfer-receipt.json').writeAsStringSync(
          jsonEncode({
            'originalFile': fresh.path,
            'originalBytes': terminalBytes.length,
            'originalSHA256': sha256.convert(terminalBytes).toString(),
            'gzipFile': compressed.path,
            'gzipBytes': compressed.lengthSync(),
            'gzipSHA256':
                sha256.convert(compressed.readAsBytesSync()).toString(),
            'originalPreserved': true,
          }),
          flush: true,
        );
        Map<String, dynamic>? recordingEvidence;
        if (recording) {
          final videoPath = actualSetEnd['videoLocalPath'];
          expect(videoPath, isA<String>());
          final video = File(videoPath as String);
          expect(video.existsSync(), isTrue);
          expect(video.lengthSync(), inInclusiveRange(1, 256 * 1024 * 1024));
          final manifest = actualSetEnd['deepAnalysis'] as Map;
          expect(manifest['timebase'], 'video_ms');
          final reps = manifest['reps'] as List;
          expect(reps, isNotEmpty);
          final player = VideoPlayerController.file(video);
          try {
            await player.initialize().timeout(const Duration(seconds: 20));
            expect(
              player.value.duration.inMilliseconds,
              inInclusiveRange(1, 180000),
            );
            var previousEnd = 0.0;
            for (var i = 0; i < reps.length; i++) {
              final rep = reps[i] as Map;
              final start = (rep['startMs'] as num).toDouble();
              final end = (rep['endMs'] as num).toDouble();
              expect(rep['repIndex'], i + 1);
              expect(start.isFinite && end.isFinite, isTrue);
              expect(start, greaterThanOrEqualTo(previousEnd));
              expect(end, greaterThan(start));
              expect(
                end,
                lessThanOrEqualTo(player.value.duration.inMilliseconds + 100),
              );
              previousEnd = end;
            }
            recordingEvidence = {
              'videoPath': videoPath,
              'durationMs': player.value.duration.inMilliseconds,
              'sourceDurationMs': sourceDurationMs,
              'durationDeltaMsDescriptiveOnly':
                  player.value.duration.inMilliseconds - sourceDurationMs!,
              'width': player.value.size.width,
              'height': player.value.size.height,
              'manifest': manifest,
              'uploaded': false,
              'queuePersisted': false,
            };
          } finally {
            await player.dispose();
          }
        }
        // Genuine clips are never retuned to force a warning. A separately labelled native
        // synthetic geometry witness exercises positive delivery and occlusion expiry end-to-end.
        final positiveWitness = await channel!.invokeMethod(
          'runExperimentalCoachingCandidateSelfTest',
          {'stage': 'positive'},
        );
        expect((positiveWitness as Map)['synthetic'], isTrue);
        final syntheticProposal = await syntheticPresented.future.timeout(
          const Duration(seconds: 10),
        );
        await tester.pump();
        expect(find.text('합성 테스트 · 실험 코칭'), findsOneWidget);
        expect(
          find.byType(ExperimentalCoachingCandidateBanner),
          findsOneWidget,
        );
        final occlusionWitness = await channel!.invokeMethod(
          'runExperimentalCoachingCandidateSelfTest',
          {'stage': 'occluded'},
        );
        expect((occlusionWitness as Map)['synthetic'], isTrue);
        final syntheticClear = await syntheticCleared.future.timeout(
          const Duration(seconds: 10),
        );
        await tester.pump();
        expect(find.byType(ExperimentalCoachingCandidateBanner), findsNothing);
        expect(
          syntheticClear['previousProposalId'],
          syntheticProposal['proposalId'],
        );
        File(
          '${output.path}/synthetic-proposal-channel-witness.json',
        ).writeAsStringSync(
          jsonEncode({
            'synthetic': true,
            'positiveFromActualVideo': false,
            'productionCandidateEngine': true,
            'productionMethodChannel': true,
            'productionBanner': true,
            'proposal': syntheticProposal,
            'clear': syntheticClear,
            'positiveWitness': positiveWitness,
            'occlusionWitness': occlusionWitness,
            'TTSRequested': false,
            'actualVideoProposalCount': proposals
                .where(
                  (packet) =>
                      (packet['context'] as Map)['source_kind'] !=
                      'synthetic_fixture',
                )
                .length,
          }),
          flush: true,
        );
        File('${output.path}/proposal-delivery.json').writeAsStringSync(
          jsonEncode({'proposals': proposals, 'clears': clears}),
          flush: true,
        );
        expect(noHttp.attempts, 0);
        expect(
          flutterErrors,
          0,
          reason: 'No rendering error may be hidden by success evidence',
        );
        expect(pendingTestException, isNull);
        File('${output.path}/success.json').writeAsStringSync(
          jsonEncode({
            'scope':
                'actual_native_existing_video_engineering_candidate_capture',
            'synthetic_input': false,
            'hostAttemptId': attemptId,
            'exerciseId': exercise,
            'new_camera_recording': false,
            'new_native_video_as_camera_recording': recording,
            if (recordingEvidence != null) 'recording': recordingEvidence,
            'uploaded': false,
            'native_counter_unchanged_by_test': true,
            'DartNetworkAttempts': noHttp.attempts,
            'realPreferencesBackendUsed': false,
            'realRecordWrites': 0,
            'TTSRequested': false,
            'flutterErrorCount': flutterErrors,
            'terminalFileName': fresh.path.split('/').last,
            'namespace': namespace,
            'candidateCounts': candidateCounts,
            'knownCandidateDecisions': knownCandidateDecisions,
            'stoppedGenerationFrames': stoppedGenerationFrames,
            'flushWithoutCandidate': flushWithoutCandidate,
            'records': rows.length,
            'frameRows':
                rows.where((r) => r['type'] == 'terminal_frame').length,
            'repRows': rows.where((r) => r['type'] == 'terminal_rep').length,
            'footer': rows.last,
            'poseUpdateEvents': observed.length,
            'warning':
                'Complete diagnostic flush is not anatomical lockout or accuracy proof',
          }),
          flush: true,
        );
        stage('all_assertions_passed');
      } catch (error, stack) {
        File('${output.path}/failure.json').writeAsStringSync(
          jsonEncode({
            'testFailed': true,
            'type': error.runtimeType.toString(),
            'lastStage': stages.isEmpty ? null : stages.last['stage'],
          }),
          flush: true,
        );
        File('${output.path}/private-errors.txt').writeAsStringSync(
          '$error\n$stack\n',
          mode: FileMode.append,
          flush: true,
        );
        stage('test_error', {'type': error.runtimeType.toString()});
        rethrow;
      } finally {
        try {
          await tester
              .pumpWidget(const SizedBox())
              .timeout(const Duration(seconds: 10));
        } catch (error, stack) {
          File('${output.path}/cleanup-failure.json').writeAsStringSync(
            jsonEncode({
              'cleanupFailed': true,
              'type': error.runtimeType.toString(),
            }),
            flush: true,
          );
          File('${output.path}/private-errors.txt').writeAsStringSync(
            '$error\n$stack\n',
            mode: FileMode.append,
            flush: true,
          );
          rethrow;
        } finally {
          channel?.setMethodCallHandler(null);
          HttpOverrides.global = oldHttp;
          FlutterError.onError = oldError;
          stage('test_finally');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
