// Real authenticated report/video for the separately authorized IMG9900 job.
// Does not submit an upload or create/delete accounts. Identity invalidation is
// simulated at the provider boundary so the saved login remains untouched.
import 'dart:convert';
import 'dart:io';

import 'package:bpt/core/theme/app_theme.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/features/workout/data/deep_analysis_service.dart';
import 'package:bpt/features/workout/screens/deep_analysis_report_screen.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('authorized existing report playback and identity invalidation',
      (tester) async {
    const jobId = String.fromEnvironment('DEEP_REPORT_JOB_ID');
    expect(jobId, isNotEmpty,
        reason: 'Use only the authorized IMG9900 completed job');
    final prefs = await SharedPreferences.getInstance();
    final identity = StateProvider<String?>((ref) => null);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWith((ref) => ref.watch(identity)),
    ]);
    addTearDown(container.dispose);
    final auth = container.read(authNotifierProvider);
    expect(await auth.tryAutoLogin(), isTrue);
    expect(auth.currentUser, isNotNull);
    container.read(identity.notifier).state = auth.currentUser!.id;
    final service = container.read(deepAnalysisServiceProvider);
    final job = await service.fetchJob(jobId, CancelToken());
    expect(job.status, 'done');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const DeepAnalysisReportScreen(jobId: jobId))));
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (find.byType(VideoPlayer).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(VideoPlayer), findsOneWidget);
    final player =
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;
    expect(player.value.isInitialized, isTrue);
    final target =
        Duration(milliseconds: player.value.duration.inMilliseconds ~/ 2);
    expect(target.inMilliseconds, greaterThan(0));
    tester
        .widget<DeepAnalysisReport>(find.byType(DeepAnalysisReport))
        .onSeek(target);
    final seekDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (player.value.position < target - const Duration(milliseconds: 500) &&
        DateTime.now().isBefore(seekDeadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(player.value.position.inMilliseconds,
        greaterThanOrEqualTo(target.inMilliseconds - 500));
    final seekPosition = player.value.position.inMilliseconds;
    final duration = player.value.duration.inMilliseconds;
    await player.pause();
    container.read(identity.notifier).state = null;
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.text('계정이 바뀌었어. 기록에서 다시 열어 줘.'), findsOneWidget);
    expect(auth.isLoggedIn, isTrue,
        reason: 'Only the test identity provider changed');
    final docs = await getApplicationDocumentsDirectory();
    final evidence = Directory('${docs.path}/deep_validation');
    await evidence.create(recursive: true);
    await File('${evidence.path}/existing_report.json')
        .writeAsString(jsonEncode({
      'scope': 'authorized_existing_job_report',
      'jobId': jobId,
      'durationMs': duration,
      'seekTargetMs': target.inMilliseconds,
      'seekPositionMs': seekPosition,
      'identityInvalidation': 'provider_boundary_simulation',
      'savedLoginPreserved': auth.isLoggedIn,
    }));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
