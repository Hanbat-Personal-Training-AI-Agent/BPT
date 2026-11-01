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
  testWidgets('explicit existing-video terminal capture without user writes',
      (tester) async {
    final docs = await getApplicationDocumentsDirectory();
    final output = Directory(
        '${docs.path}/terminal_capture_validation/${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    void stage(String name, [Map<String, dynamic> fields = const {}]) {
      File('${output.path}/progress.json').writeAsStringSync(
          jsonEncode({
            'stage': name,
            'at': DateTime.now().toUtc().toIso8601String(),
            ...fields
          }),
          flush: true);
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
          flush: true);
      oldError?.call(details);
    };
    MethodChannel? channel;
    final ready = Completer<void>();
    final setEnd = Completer<Map>();
    final observed = <Map<String, dynamic>>[];
    try {
      final config =
          jsonDecode(File('${docs.path}/bpt_demo.json').readAsStringSync())
              as Map;
      for (final key in [
        'BPT_TERMINAL_EVIDENCE',
        'BPT_TERMINAL_CANDIDATE',
        'BPT_TERMINAL_EOF_FLUSH'
      ]) {
        expect('${config[key]}', '1',
            reason: 'Explicit host-owned opt-in required');
      }
      expect('${config['BPT_VOICE_MUTE']}', '1');
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
          isTrue);
      expect(File('${docs.path}/$clip').existsSync(), isTrue);
      int? sourceDurationMs;
      if (recording) {
        final sourcePlayer =
            VideoPlayerController.file(File('${docs.path}/$clip'));
        try {
          await sourcePlayer.initialize().timeout(const Duration(seconds: 20));
          sourceDurationMs = sourcePlayer.value.duration.inMilliseconds;
          expect(sourceDurationMs, greaterThan(0));
        } finally {
          await sourcePlayer.dispose();
        }
      }
      final exercise = '${config['BPT_TERMINAL_TEST_EXERCISE'] ?? ''}';
      expect(['squat', 'pushup', 'barbell-row'], contains(exercise));
      expect(recording, exercise == 'barbell-row',
          reason:
              'Only the separately authorized full row capture records video');
      if (recording) {
        final videos = Directory('${docs.path}/workout_videos');
        final count = videos.existsSync()
            ? videos
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.mp4'))
                .length
            : 0;
        expect(count, lessThan(20),
            reason: 'Never permit recorder pruning of an existing video');
      }
      final logDir = Directory('${docs.path}/video_runs');
      final before = logDir.existsSync()
          ? logDir
              .listSync()
              .whereType<File>()
              .where((f) =>
                  f.path.split('/').last.startsWith('terminal_') &&
                  f.path.endsWith('.jsonl'))
              .map((f) => f.path)
              .toSet()
          : <String>{};
      expect(before.length, lessThan(3),
          reason: 'Preserve/archive prior files before cap; never delete here');
      stage('preflight_pass',
          {'terminalFilesBefore': before.length, 'exercise': exercise});
      await tester
          .pumpWidget(MaterialApp(
              home: Scaffold(
                  body: UiKitView(
            viewType: 'bpt/native_pose_camera',
            creationParams: {'exerciseId': exercise},
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: (id) async {
              channel = MethodChannel('bpt/native_pose_camera/$id');
              channel!.setMethodCallHandler((call) async {
                if (call.method == 'onSetEnd' && !setEnd.isCompleted) {
                  setEnd.complete(call.arguments as Map);
                }
                if (call.method == 'onPoseUpdate') {
                  final args = call.arguments as Map;
                  observed.add({'rep': args['rep'], 'status': args['status']});
                }
                // Deliberately no speech response, account or result persistence.
                return null;
              });
              await channel!.invokeMethod('setVoiceMuted', {'muted': true});
              ready.complete();
            },
          ))))
          .timeout(const Duration(seconds: 15));
      await ready.future.timeout(const Duration(seconds: 20));
      stage('production_native_view_started');
      final actualSetEnd =
          await setEnd.future.timeout(const Duration(minutes: 3));
      stage('actual_native_set_end_received');
      File? fresh;
      List<Map> rows = [];
      final until = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(until)) {
        final files = logDir
            .listSync()
            .whereType<File>()
            .where((f) =>
                f.path.split('/').last.startsWith('terminal_') &&
                f.path.endsWith('.jsonl') &&
                !before.contains(f.path))
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
          expect(player.value.duration.inMilliseconds,
              inInclusiveRange(1, 180000));
          var previousEnd = 0.0;
          for (var i = 0; i < reps.length; i++) {
            final rep = reps[i] as Map;
            final start = (rep['startMs'] as num).toDouble();
            final end = (rep['endMs'] as num).toDouble();
            expect(rep['repIndex'], i + 1);
            expect(start.isFinite && end.isFinite, isTrue);
            expect(start, greaterThanOrEqualTo(previousEnd));
            expect(end, greaterThan(start));
            expect(end,
                lessThanOrEqualTo(player.value.duration.inMilliseconds + 100));
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
            'queuePersisted': false
          };
        } finally {
          await player.dispose();
        }
      }
      expect(noHttp.attempts, 0);
      expect(flutterErrors, 0,
          reason: 'No rendering error may be hidden by success evidence');
      expect(tester.takeException(), isNull);
      File('${output.path}/success.json').writeAsStringSync(
          jsonEncode({
            'scope': 'actual_native_existing_video_terminal_candidate_capture',
            'synthetic_input': false,
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
            'terminalFileName': fresh!.path.split('/').last,
            'records': rows.length,
            'frameRows':
                rows.where((r) => r['type'] == 'terminal_frame').length,
            'repRows': rows.where((r) => r['type'] == 'terminal_rep').length,
            'footer': rows.last,
            'poseUpdateEvents': observed.length,
            'warning':
                'Complete diagnostic flush is not anatomical lockout or accuracy proof'
          }),
          flush: true);
      stage('all_assertions_passed');
    } finally {
      try {
        await tester
            .pumpWidget(const SizedBox())
            .timeout(const Duration(seconds: 10));
      } catch (error, stack) {
        File('${output.path}/cleanup-failure.json').writeAsStringSync(
            jsonEncode(
                {'cleanupFailed': true, 'type': error.runtimeType.toString()}),
            flush: true);
        File('${output.path}/private-errors.txt').writeAsStringSync(
            '$error\n$stack\n',
            mode: FileMode.append,
            flush: true);
        rethrow;
      } finally {
        channel?.setMethodCallHandler(null);
        HttpOverrides.global = oldHttp;
        FlutterError.onError = oldError;
        stage('test_finally');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
