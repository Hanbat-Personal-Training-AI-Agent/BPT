// Offline renderer of an actual, hash-bound server response and its original video.
// Never execute the normal main, sign in, fetch, upload or persist a workout.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bpt/core/theme/app_theme.dart';
import 'package:bpt/features/workout/data/deep_analysis_service.dart';
import 'package:bpt/features/workout/screens/deep_analysis_report_screen.dart';
// Test helper uses the already lock-pinned transitive package; no dependency change.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

class _NoHttp extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Offline actual report has no transport');
  }
}

Future<void> main() async {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  b.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  var frames = 0;
  b.addTimingsCallback((values) {
    frames += values.length;
  });
  testWidgets(
    'actual server payload and original local native recording render',
    (tester) async {
      final docs = await getApplicationDocumentsDirectory();
      final out = Directory(
        '${docs.path}/actual_deep_validation/output_${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true);
      final stages = <Map<String, dynamic>>[];
      void stage(String name, [Map<String, dynamic> fields = const {}]) {
        stages.add({
          'stage': name,
          'at': DateTime.now().toUtc().toIso8601String(),
          'frames': frames,
          'lifecycle': b.lifecycleState?.name,
          ...fields,
        });
        File(
          '${out.path}/progress.json',
        ).writeAsStringSync(jsonEncode({'stages': stages}), flush: true);
      }

      File local(String rel) {
        if (rel.startsWith('/') || rel.split('/').contains('..')) {
          throw StateError('Only bound Documents-relative input');
        }
        return File('${docs.path}/$rel');
      }

      final oldHttp = HttpOverrides.current;
      final deny = _NoHttp();
      HttpOverrides.global = deny;
      SharedPreferences.setMockInitialValues({});
      final oldError = FlutterError.onError;
      var errors = 0;
      FlutterError.onError = (details) {
        errors++;
        File('${out.path}/private-errors.txt').writeAsStringSync(
          '$details\n${details.stack}\n',
          mode: FileMode.append,
        );
        oldError?.call(details);
      };
      VideoPlayerController? player;
      File? ownedResponse;
      File? ownedBinding;
      String? ownedResponseHash;
      String? ownedBindingHash;
      try {
        stage('entry');
        final bindingFile =
            File('${docs.path}/actual_deep_validation/input-binding.json');
        final bindingBytes = await bindingFile.readAsBytes();
        final binding = jsonDecode(utf8.decode(bindingBytes)) as Map;
        ownedBinding = bindingFile;
        ownedBindingHash = sha256.convert(bindingBytes).toString();
        expect(
          binding['scope'],
          'new_actual_row_native_to_deep_offline_phone_render',
        );
        expect(
            (binding['jobEnvelopeRelativePath'] as String)
                .startsWith('actual_deep_validation/input/'),
            isTrue);
        final response = local(binding['jobEnvelopeRelativePath'] as String);
        final video = local(binding['videoRelativePath'] as String);
        final responseHash =
            sha256.convert(await response.readAsBytes()).toString();
        final videoHash =
            (await sha256.bind(video.openRead()).first).toString();
        expect(responseHash, binding['jobEnvelopeSHA256']);
        ownedResponse = response;
        ownedResponseHash = responseHash;
        expect(videoHash, binding['videoSHA256']);
        expect(videoHash, binding['gpuInputVideoSHA256']);
        final job = DeepAnalysisJob.fromJson(
          (jsonDecode(await response.readAsString()) as Map)
              .cast<String, dynamic>(),
        );
        expect(job.status, 'done');
        final report = (job.result!['report'] as Map).cast<String, dynamic>();
        final reps = report['reps'] as List;
        expect(reps, isNotEmpty);
        stage('actual_job_parsed_hashes_bound', {
          'repCount': reps.length,
          'timelineCount': (report['timeline'] as List).length,
        });
        player = VideoPlayerController.file(video);
        await player.initialize().timeout(const Duration(seconds: 30));
        expect(player.value.isInitialized, isTrue);
        await player.setVolume(0);
        expect(player.value.duration.inMilliseconds, greaterThan(0));
        stage('original_local_video_initialized');
        final seek = Completer<Map<String, int>>();
        await tester
            .pumpWidget(
              MaterialApp(
                theme: AppTheme.darkTheme,
                home: Scaffold(
                  body: SafeArea(
                    child: DeepAnalysisReport(
                      report: report,
                      video: SizedBox(
                        height: 220,
                        child: AspectRatio(
                          aspectRatio: player.value.aspectRatio,
                          child: VideoPlayer(player),
                        ),
                      ),
                      onSeek: (target) async {
                        try {
                          await player!
                              .seekTo(target)
                              .timeout(const Duration(seconds: 10));
                          await player.play();
                          await Future<void>.delayed(
                            const Duration(milliseconds: 200),
                          );
                          await player.pause();
                          if (!seek.isCompleted) {
                            seek.complete({
                              'targetMs': target.inMilliseconds,
                              'reportedPositionMs':
                                  player.value.position.inMilliseconds,
                            });
                          }
                        } catch (e, st) {
                          if (!seek.isCompleted) seek.completeError(e, st);
                        }
                      },
                    ),
                  ),
                ),
              ),
            )
            .timeout(const Duration(seconds: 15));
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(find.byType(DeepAnalysisReport), findsOneWidget);
        expect(find.byType(VideoPlayer), findsOneWidget);
        await tester
            .scrollUntilVisible(
              find.byType(ExpansionTile).first,
              200,
              maxScrolls: 60,
            )
            .timeout(const Duration(seconds: 20));
        await tester
            .tap(find.byType(ExpansionTile).first)
            .timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join('\n');
        expect(text.contains('null°') || text.contains('NaN'), isFalse);
        expect(errors, 0);
        expect(tester.takeException(), isNull);
        expect(deny.attempts, 0);
        expect(frames, greaterThan(0));
        File('${out.path}/success.json').writeAsStringSync(
          jsonEncode({
            'scope':
                'actual_server_report_offline_production_widget_same_original_native_video',
            'syntheticReport': false,
            'serverResponseSHA256': responseHash,
            'videoSHA256': videoHash,
            'parsedByProductionDeepAnalysisJob': true,
            'reportRepCount': reps.length,
            'timelineCount': (report['timeline'] as List).length,
            'originalVideoDurationMs': player.value.duration.inMilliseconds,
            'nativeVideoInitialized': true,
            'productionDeepAnalysisReportRendered': true,
            'firstRepExpanded': true,
            'noNullDegreeOrNaNVisible': true,
            'renderedFrameTimingCount': frames,
            'networkAttempts': deny.attempts,
            'realPreferencesBackendUsed': false,
            'realRecordWrites': 0,
            'flutterErrors': errors,
            'HTTPAuthOrSavedAccountFlowTested': false,
            'TTSRequested': false,
            'independentAccuracyOrGTClaim': false,
          }),
          flush: true,
        );
        stage('all_assertions_passed');
      } catch (error, stack) {
        File('${out.path}/failure.json').writeAsStringSync(
            jsonEncode({
              'type': error.runtimeType.toString(),
              'lastStage': stages.last['stage']
            }),
            flush: true);
        File('${out.path}/private-errors.txt').writeAsStringSync(
            '$error\n$stack\n',
            mode: FileMode.append,
            flush: true);
        stage('test_error', {'type': error.runtimeType.toString()});
        rethrow;
      } finally {
        try {
          try {
            await tester
                .pumpWidget(const SizedBox())
                .timeout(const Duration(seconds: 10));
          } finally {
            await player?.dispose();
          }
          for (final entry in [
            (ownedResponse, ownedResponseHash),
            (ownedBinding, ownedBindingHash)
          ]) {
            final file = entry.$1;
            final expected = entry.$2;
            if (file != null && expected != null && file.existsSync()) {
              expect(
                  sha256.convert(file.readAsBytesSync()).toString(), expected,
                  reason: 'Never delete an externally modified input');
              file.deleteSync();
            }
          }
          File('${out.path}/owned-input-cleanup.json').writeAsStringSync(
              jsonEncode({
                'ownedServerPayloadVerified': ownedResponse != null,
                'ownedServerPayloadAbsent':
                    ownedResponse == null ? null : !ownedResponse.existsSync(),
                'ownedBindingAbsent':
                    ownedBinding == null ? null : !ownedBinding.existsSync(),
                'originalVideoNotDeleted': true
              }),
              flush: true);
        } catch (error, stack) {
          File('${out.path}/cleanup-failure.json').writeAsStringSync(
              jsonEncode({
                'cleanupFailed': true,
                'type': error.runtimeType.toString()
              }),
              flush: true);
          File('${out.path}/private-errors.txt').writeAsStringSync(
              '$error\n$stack\n',
              mode: FileMode.append,
              flush: true);
          rethrow;
        } finally {
          HttpOverrides.global = oldHttp;
          FlutterError.onError = oldError;
          stage('test_finally');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
