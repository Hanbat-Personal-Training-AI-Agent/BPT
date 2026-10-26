// Local-only device evidence: actual XS/native reps and recording, zero deep API
// transport. Never run the trial demo autopilot or clear saved preferences.
import 'dart:convert';
import 'dart:io';

import 'package:bpt/core/theme/app_theme.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/features/onboarding/services/calibration_upload_service.dart';
import 'package:bpt/features/workout/data/deep_analysis_queue.dart';
import 'package:bpt/features/workout/data/deep_analysis_service.dart';
import 'package:bpt/features/workout/screens/native_pose_workout_screen.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

class _NoTransport extends DeepAnalysisService {
  _NoTransport({required super.userId})
      : super(
            config: const CalibrationUploadConfig(),
            tokenProvider: () async => null);
  int networkAttempts = 0;
  Never _deny() {
    networkAttempts++;
    throw StateError('Local dataset validation forbids all deep API transport');
  }

  @override
  Future<List<Map<String, dynamic>>> loadQueue() async => [];
  @override
  Future<void> saveQueue(List<Map<String, dynamic>> rows) async {}
  @override
  Future<bool> canUpload(DeepAnalysisCapture capture) async => false;
  @override
  Future<String> upload(DeepAnalysisCapture capture, CancelToken cancel,
          {void Function(String)? onProgress}) async =>
      _deny();
  @override
  Future<DeepAnalysisJob> fetchJob(String jobId, CancelToken cancel) async =>
      _deny();
  @override
  Future<String> retryJob(String jobId, CancelToken cancel) async => _deny();
  @override
  Future<File> downloadVideo(String jobId, CancelToken cancel) async => _deny();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('local native capture only — no dataset upload', (tester) async {
    final docs = await getApplicationDocumentsDirectory();
    final configFile = File('${docs.path}/bpt_demo.json');
    expect(await configFile.exists(), isTrue,
        reason:
            'Device owner must select a single local clip in bpt_demo.json');
    final config = jsonDecode(await configFile.readAsString()) as Map;
    final clip = '${config['BPT_CAMERA_VIDEO'] ?? ''}';
    expect(clip.isNotEmpty && !clip.contains(','), isTrue);
    expect('${config['BPT_CAMERA_VIDEO_LOOPS'] ?? '1'}', '1');
    expect(
        await File(clip.startsWith('/') ? clip : '${docs.path}/$clip').exists(),
        isTrue);

    // The real recorder prunes to 20 files. Never let this validation remove an
    // existing recording as a side effect of starting a new set.
    final recordings = Directory('${docs.path}/workout_videos');
    if (await recordings.exists()) {
      final existing = await recordings
          .list()
          .where((file) => file.path.endsWith('.mp4'))
          .length;
      expect(existing, lessThan(20),
          reason:
              'Device owner must preserve existing recordings before this run');
    }
    final prefs = await SharedPreferences.getInstance();
    // Real saved login is restored normally. No account creation, token injection,
    // preference clearing or workout metadata save takes place in this harness.
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      deepAnalysisServiceProvider.overrideWith((ref) {
        final service = _NoTransport(userId: ref.watch(currentUserIdProvider));
        ref.onDispose(service.close);
        return service;
      }),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(authNotifierProvider).tryAutoLogin(), isTrue,
        reason: 'Existing remembered login must be available');
    expect(container.read(currentUserIdProvider), isNotNull);
    final service = container.read(deepAnalysisServiceProvider) as _NoTransport;
    final queue = container.read(deepAnalysisQueueProvider.notifier);
    await queue.ready;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const NativePoseWorkoutScreen(
                exerciseId: 'barbell-row',
                targetReps: int.fromEnvironment('DEEP_LOCAL_TARGET_REPS',
                    defaultValue: 3),
                targetSets: 1))));
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (container.read(deepAnalysisQueueProvider).isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final rows = container.read(deepAnalysisQueueProvider).values.toList();
    expect(rows, hasLength(1),
        reason: 'Actual native reps and BPT_SET_RECORDING=1 are required');
    final row = rows.single;
    expect(row['status'], 'waiting');
    expect(service.networkAttempts, 0);
    final manifest = row['manifest'] as Map;
    expect(manifest['timebase'], 'video_ms');
    final reps = manifest['reps'] as List;
    expect(reps, isNotEmpty);
    var previousEnd = 0.0;
    for (var i = 0; i < reps.length; i++) {
      final rep = reps[i] as Map;
      final start = (rep['startMs'] as num).toDouble();
      final end = (rep['endMs'] as num).toDouble();
      expect(rep['repIndex'], i + 1);
      expect(start.isFinite && end.isFinite, isTrue);
      expect(start, greaterThanOrEqualTo(previousEnd));
      expect(end, greaterThan(start));
      expect(end, lessThanOrEqualTo(60000));
      previousEnd = end;
    }
    final video = File(row['videoPath'] as String);
    expect(await video.length(), inInclusiveRange(1, 32 * 1024 * 1024));
    final player = VideoPlayerController.file(video);
    try {
      await player.initialize();
      expect(player.value.duration.inMilliseconds, inInclusiveRange(1, 60100));
      expect(previousEnd,
          lessThanOrEqualTo(player.value.duration.inMilliseconds + 100));
      final size = player.value.size;
      expect([size.width.round(), size.height.round()]..sort(), [720, 1280]);
      final evidence = Directory('${docs.path}/deep_validation');
      await evidence.create(recursive: true);
      await File('${evidence.path}/local_capture.json')
          .writeAsString(jsonEncode({
        'scope': 'local_native_capture_only',
        'uploaded': false,
        'queuePersisted': false,
        'networkAttempts': service.networkAttempts,
        'clip': clip.split('/').last,
        'videoPath': video.path,
        'durationMs': player.value.duration.inMilliseconds,
        'width': size.width,
        'height': size.height,
        'manifest': manifest,
      }));
    } finally {
      await player.dispose();
      // Do not tap the results button: that would save a workout to the account.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
