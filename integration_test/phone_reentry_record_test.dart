// Opt-in phone mode `reentry`: the same process opens the production native
// camera view twice, saves each set through the real result screen into an
// in-memory account store, reopens both records, and plays each recording.
// Never touches real preferences, records, network or pre-existing videos.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bpt/core/i18n/locale_provider.dart';
import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/data/mock_data.dart';
import 'package:bpt/data/repositories/workout_repository.dart';
import 'package:bpt/features/workout/data/native_pose_channel.dart';
import 'package:bpt/features/workout/data/workout_evidence.dart';
import 'package:bpt/features/workout/screens/workout_result_screen.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:bpt/services/sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'phone_lifecycle_guard.dart';

const testName = 'same-process camera reentry, record save, reopen and replay';
const _uid = 'phone-reentry-test-owner';

class _NoHttp extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Reentry test forbids transport');
  }
}

class _Offline implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.none];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _RefuseTransport implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) {
    calls++;
    throw StateError('Reentry test forbids transport');
  }

  @override
  void close({bool force = false}) {}
}

Map<String, int> _videos(Directory dir) => dir.existsSync()
    ? {
        for (final f in dir.listSync().whereType<File>())
          f.path.split('/').last: f.lengthSync(),
      }
    : {};

void registerPhoneReentryRecordTest({
  required void Function(String) onOutputCreated,
  required PhoneLifecycleGuard lifecycle,
}) {
  testWidgets(testName, (tester) async {
    final docs = await getApplicationDocumentsDirectory();
    final output = Directory(
      '${docs.path}/coaching_candidate_validation/${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    onOutputCreated(output.path.substring(docs.path.length + 1));
    final stages = <Map<String, dynamic>>[];
    void stage(String name, [Map<String, dynamic> fields = const {}]) {
      final now = DateTime.now().toUtc().toIso8601String();
      stages.add({'stage': name, 'at': now, ...fields});
      File('${output.path}/progress.json').writeAsStringSync(
          jsonEncode({'stages': stages, 'stage': name, 'at': now, ...fields}),
          flush: true);
    }

    void save(String name, Object value) => File('${output.path}/$name')
        .writeAsStringSync(jsonEncode(value), flush: true);

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
    final videoDir = Directory('${docs.path}/workout_videos');
    final videosBefore = _videos(videoDir);
    final ownedVideos = <String>{};
    final transport = _RefuseTransport();
    try {
      final config =
          jsonDecode(File('${docs.path}/bpt_demo.json').readAsStringSync())
              as Map;
      for (final key in [
        'BPT_SET_RECORDING',
        'BPT_TERMINAL_TEST_RECORDING',
        'BPT_VOICE_MUTE',
        'BPT_NORMAL_RUN_LOG_PRELAUNCH_ABSENT',
      ]) {
        expect('${config[key]}', '1', reason: '$key must be host opt-in');
      }
      expect('${config['BPT_TERMINAL_EVIDENCE']}', '0');
      expect('${config['BPT_CAMERA_VIDEO_LOOPS']}', '1');
      expect('${config['BPT_DEMO_AUTOPILOT'] ?? '0'}', '0');
      final exercise = '${config['BPT_TERMINAL_TEST_EXERCISE'] ?? ''}';
      expect(exercise, 'pushup');
      final clip = '${config['BPT_CAMERA_VIDEO'] ?? ''}';
      expect(
          clip.isNotEmpty &&
              !clip.contains(',') &&
              !clip.startsWith('/') &&
              !clip.split('/').contains('..'),
          isTrue);
      expect(File('${docs.path}/$clip').existsSync(), isTrue);
      final runTag = '${config['BPT_RUN_TAG'] ?? ''}';
      expect(RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(runTag), isTrue);
      final runLog = File('${docs.path}/video_runs/run_$runTag.jsonl');
      // The recorder prunes to 19 before each set; two sets must never prune.
      expect(videosBefore.keys.where((n) => n.endsWith('.mp4')).length,
          lessThanOrEqualTo(17),
          reason: 'Never permit recorder pruning of an existing video');
      stage('waiting_for_real_resumed');
      await lifecycle.beginWhenResumed();
      stage('preflight_pass', {'videosBefore': videosBefore.length});

      List<Map> runRows() {
        try {
          return runLog
              .readAsLinesSync()
              .where((l) => l.isNotEmpty)
              .map((l) => jsonDecode(l) as Map)
              .toList();
        } catch (_) {
          return [];
        }
      }

      // ── Two capture entries in one process ───────────────────────────
      final sessions = <Map<String, dynamic>>[];
      final lateEvents = <int, int>{};
      for (var entry = 1; entry <= 2; entry++) {
        final ready = Completer<void>();
        final setEnd = Completer<Map>();
        MethodChannel? channel;
        var maxRep = 0, poseUpdates = 0, repWarnings = 0;
        DateTime? disposedAt;
        final current = entry;
        final startedAt = DateTime.now();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: UiKitView(
              key: ValueKey('native-entry-$entry'),
              viewType: 'bpt/native_pose_camera',
              creationParams: {'exerciseId': exercise},
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: (id) async {
                channel = MethodChannel('bpt/native_pose_camera/$id');
                channel!.setMethodCallHandler((call) async {
                  if (disposedAt != null &&
                      DateTime.now().difference(disposedAt) >
                          const Duration(seconds: 1)) {
                    lateEvents[current] = (lateEvents[current] ?? 0) + 1;
                    return null;
                  }
                  if (call.method == NativePoseChannel.onSetEnd &&
                      !setEnd.isCompleted) {
                    setEnd.complete(call.arguments as Map);
                  }
                  if (call.method == 'onPoseUpdate') {
                    poseUpdates++;
                    final rep = (call.arguments as Map)['rep'];
                    if (rep is int && rep > maxRep) maxRep = rep;
                  }
                  if (call.method == NativePoseChannel.onFeedback &&
                      (call.arguments as Map)['scope'] == 'rep') {
                    repWarnings++;
                  }
                  return null;
                });
                await channel!.invokeMethod('setVoiceMuted', {'muted': true});
                ready.complete();
              },
            ),
          ),
        ));
        await ready.future.timeout(const Duration(seconds: 20));
        stage('entry_${entry}_native_view_started');
        final eofDeadline = DateTime.now().add(const Duration(minutes: 3));
        var rows = runRows();
        while (DateTime.now().isBefore(eofDeadline) &&
            !(rows.where((r) => r['type'] == 'video_end').length == entry &&
                rows.where((r) => r['type'] == 'session_end').length ==
                    entry)) {
          await tester.pump(const Duration(milliseconds: 200));
          rows = runRows();
        }
        expect(rows.where((r) => r['type'] == 'video_end'), hasLength(entry),
            reason: 'Entry $entry must replay the clip to its own EOF');
        expect(rows.where((r) => r['type'] == 'session_end'), hasLength(entry));
        await channel!.invokeMethod(NativePoseChannel.endSet, {'setIndex': 1});
        final end = await setEnd.future.timeout(const Duration(minutes: 2));
        final diagnostic = Map<String, dynamic>.from(await channel!
                .invokeMethod('getExperimentalCoachingCandidateDiagnostics')
            as Map);
        final videoPath = end['videoLocalPath'];
        expect(videoPath, isA<String>(),
            reason: 'Entry $entry must close its own set recording');
        final video = File(videoPath as String);
        expect(video.parent.path.endsWith('/Documents/workout_videos'), isTrue);
        expect(videosBefore.containsKey(video.path.split('/').last), isFalse);
        ownedVideos.add(video.path);
        expect(video.lengthSync(), inInclusiveRange(1, 256 * 1024 * 1024));
        expect(end['setIndex'], 1);
        expect(maxRep, greaterThan(0), reason: 'Entry $entry counted no reps');
        expect(diagnostic['processedFrames'], greaterThan(0));
        sessions.add({
          'entry': entry,
          'setEnd': end,
          'videoPath': video.path,
          'videoBytes': video.lengthSync(),
          'elapsedSeconds': DateTime.now().difference(startedAt).inSeconds,
          'reps': maxRep,
          'poseUpdates': poseUpdates,
          'repWarningEvents': repWarnings,
          'diagnostics': diagnostic,
        });
        save('entry-$entry-set-end.json', sessions.last);
        stage('entry_${entry}_set_end_received', {'reps': maxRep});
        disposedAt = DateTime.now();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
        stage('entry_${entry}_native_view_disposed');
      }
      expect(sessions[0]['videoPath'], isNot(sessions[1]['videoPath']));
      expect(lateEvents.values.fold<int>(0, (a, b) => a + b), 0,
          reason: 'A disposed camera entry must not keep delivering');

      // ── Save each set as the production result screen does ───────────
      final prefs = await SharedPreferences.getInstance();
      final api = ApiClient(baseUrl: 'http://127.0.0.1:9');
      api.dio.httpClientAdapter = transport;
      final storage = LocalStorageService(prefs);
      final queue = SyncQueueStorage(prefs, _uid);
      final sync = WorkoutSyncNotifier(api, queue, storage, _Offline());
      WorkoutRepository repository() =>
          WorkoutRepository(api, storage, queue, sync, _Offline(),
              isCurrentAccount: () => true);
      final ex = findExercise(exercise);
      Widget screen(Map<String, dynamic> result) => ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              selectedLanguageProvider.overrideWith((ref) => 'ko'),
              workoutRepositoryProvider.overrideWithValue(repository()),
            ],
            child: MaterialApp(home: WorkoutResultScreen(result: result)),
          );
      final recordIds = <String>[];
      for (final s in sessions) {
        final reps = s['reps'] as int, bad = s['repWarningEvents'] as int;
        final id =
            'phone-reentry-${s['entry']}-${DateTime.now().microsecondsSinceEpoch}';
        recordIds.add(id);
        await tester.pumpWidget(screen({
          'exerciseId': exercise,
          'exerciseName': ex.name,
          'exerciseNameKr': ex.nameKr,
          'totalReps': reps,
          'correctReps': 0,
          'incorrectReps': 0,
          'poseMetricsSummary': WorkoutEvidence.nativeSummary(
              completedReps: reps,
              recordedWarningEvents: bad,
              sets: [
                {'reps': reps, 'weightKg': null, 'badCount': bad}
              ]),
          'elapsedSeconds': s['elapsedSeconds'],
          'postureScore': null,
          'feedbackHistory': null,
          'feedbackCounts': <String, int>{},
          'targetReps': reps,
          'targetSets': 1,
          'clientRecordId': id,
          'setResults': [
            {
              ...(s['setEnd'] as Map).cast<String, dynamic>(),
              'reps': reps,
              'weightKg': null,
              'badCount': bad,
            }
          ],
        }));
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!storage.loadRecords(uid: _uid).any((r) => r.id == id) &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(storage.loadRecords(uid: _uid).any((r) => r.id == id), isTrue);
        await tester.pumpWidget(const SizedBox());
      }
      stage('records_saved', {'records': recordIds.length});

      // ── Reopen from storage (Home path) and replay each recording ────
      final reopened = await repository().getWorkoutRecords();
      expect(reopened, hasLength(2));
      expect(queue.getQueue().map((d) => d.clientRecordId).toSet(),
          recordIds.toSet(),
          reason: 'Offline records stay staged, never sent');
      final replays = <Map<String, dynamic>>[];
      for (var i = 0; i < sessions.length; i++) {
        final WorkoutRecordModel record =
            reopened.singleWhere((r) => r.id == recordIds[i]);
        expect(record.setsDetail, hasLength(1));
        expect(
            record.setsDetail.single.videoLocalPath, sessions[i]['videoPath']);
        expect(record.totalReps, sessions[i]['reps']);
        await tester.pumpWidget(screen({
          'exerciseId': record.exerciseId,
          'exerciseName': record.exerciseName,
          'exerciseNameKr': ex.nameKr,
          'totalReps': record.totalReps,
          'correctReps': record.correctReps,
          'incorrectReps': record.incorrectReps,
          'elapsedSeconds': record.durationSeconds,
          'postureScore': record.postureScore,
          ...record.resultEvidenceFields,
          'feedbackHistory': record.feedbackNotes,
          'targetReps': record.targetReps,
          'targetSets': record.targetSets,
          'isHistory': true,
          'clientRecordId': record.id,
          'date': record.date,
        }));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.textContaining('녹화 영상이 없어'), findsNothing);
        final play = find.byIcon(Icons.play_arrow_rounded);
        expect(play, findsOneWidget);
        await tester.ensureVisible(play);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(play);
        VideoPlayerController? controller;
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
          final bars = find
              .byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_ReplayProgressBar')
              .evaluate();
          controller = bars.isEmpty
              ? null
              : (bars.first.widget as dynamic).controller
                  as VideoPlayerController?;
          if (controller != null &&
              controller.value.isPlaying &&
              controller.value.position > const Duration(milliseconds: 500)) {
            break;
          }
        }
        expect(controller, isNotNull, reason: 'Replay ${i + 1} never opened');
        expect(controller!.value.isInitialized, isTrue);
        expect(controller.value.hasError, isFalse);
        expect(controller.value.isPlaying, isTrue);
        expect(controller.value.position,
            greaterThan(const Duration(milliseconds: 500)));
        expect(controller.dataSource,
            Uri.file(sessions[i]['videoPath'] as String).toString());
        replays.add({
          'recordId': record.id,
          'videoPath': sessions[i]['videoPath'],
          'durationMs': controller.value.duration.inMilliseconds,
          'positionMs': controller.value.position.inMilliseconds,
          'width': controller.value.size.width,
          'height': controller.value.size.height,
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 300));
      }
      stage('replays_verified');
      sync.dispose();
      lifecycle.assertUninterrupted();
      expect(noHttp.attempts, 0);
      expect(transport.calls, 0);
      expect(flutterErrors, 0);
      expect(tester.takeException(), isNull);
      save('success.json', {
        'scope': 'same_process_native_reentry_record_save_reopen_replay',
        'entries': sessions.length,
        'sessions': sessions
            .map((s) => {
                  ...s,
                  'setEnd': null,
                  'deepAnalysisPresent':
                      (s['setEnd'] as Map)['deepAnalysis'] != null
                })
            .toList(),
        'lateEventsAfterDispose': 0,
        'recordsSaved': recordIds.length,
        'recordsReopened': reopened.length,
        'queuedUnsent': queue.getQueue().length,
        'replays': replays,
        'DartNetworkAttempts': noHttp.attempts,
        'transportCalls': transport.calls,
        'realPreferencesBackendUsed': false,
        'realRecordWrites': 0,
        'TTSRequested': false,
        'accuracyClaim': false,
      });
      stage('all_assertions_passed');
    } catch (error, stack) {
      save('failure.json', {
        'testFailed': true,
        'type': error.runtimeType.toString(),
        'lastStage': stages.isEmpty ? null : stages.last['stage'],
      });
      File('${output.path}/private-errors.txt').writeAsStringSync(
          '$error\n$stack\n',
          mode: FileMode.append,
          flush: true);
      stage('test_error', {'type': error.runtimeType.toString()});
      rethrow;
    } finally {
      try {
        await tester
            .pumpWidget(const SizedBox())
            .timeout(const Duration(seconds: 10));
      } finally {
        // Test-owned recordings only; pre-existing videos are never touched.
        for (final path in ownedVideos) {
          try {
            File(path).deleteSync();
          } catch (_) {}
        }
        final after = _videos(videoDir);
        save('video-cleanup.json', {
          'before': videosBefore,
          'after': after,
          'ownedDeleted': ownedVideos.toList(),
          'restored': after.length == videosBefore.length &&
              videosBefore.entries.every((e) => after[e.key] == e.value),
        });
        HttpOverrides.global = oldHttp;
        FlutterError.onError = oldError;
        save('lifecycle.json', lifecycle.snapshot);
        lifecycle.dispose();
        stage('test_finally');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 9)));
}
