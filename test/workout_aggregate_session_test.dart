import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:bpt/services/calendar_service.dart';
import 'package:bpt/features/home/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:bpt/features/report/providers/report_analysis_provider.dart';
import 'package:bpt/features/workout/data/workout_evidence.dart';

import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/data/repositories/workout_repository.dart';
import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/features/home/providers/home_provider.dart';
import 'package:bpt/services/dashboard_service.dart';
import 'package:bpt/services/workout_records_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/session_fixture.dart';

class _Dashboard extends DashboardService {
  _Dashboard(super.client);
  final calls = <Completer<DashboardSummary>>[];
  @override
  Future<DashboardSummary> fetchSummary({bool Function()? sessionGuard}) {
    final call = Completer<DashboardSummary>();
    calls.add(call);
    return call.future;
  }
}

DashboardSummary _summary(int n) => DashboardSummary(
    date: DateTime.now(),
    todayWorkoutMinutes: n,
    todayCompletedSets: n,
    todayTotalReps: n,
    weeklyCompletedCount: n,
    daysSinceLastScan: n);

class _Repo implements IWorkoutRepository {
  @override
  Future<List<WorkoutRecordModel>> getWorkoutRecords() async => [];
  @override
  Future<WorkoutRecordModel> submitWorkoutRecord(
          WorkoutMetadataRequestDto dto) =>
      throw UnimplementedError();
}

class _AggregateServer implements HttpClientAdapter {
  final pending = <(RequestOptions, Completer<ResponseBody>)>[];
  final tokens = <String?>[];
  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    tokens.add(options.headers['Authorization'] as String?);
    final gate = Completer<ResponseBody>();
    pending.add((options, gate));
    return gate.future;
  }

  void finish(String owner, int value, {int status = 200}) {
    for (final (request, gate) in pending) {
      if (gate.isCompleted ||
          request.headers['Authorization'] != 'Bearer token-$owner') {
        continue;
      }
      final data = switch (request.path) {
        '/users/me/dashboard' => {
            'date': DateTime.now().toIso8601String().split('T').first,
            'todayTotalReps': value,
            'todayCompletedSets': value,
            'completedSetsEvidenceVersion': 1
          },
        '/workouts/calendar' => {
            'workoutDates': ['2026-11-02'],
            'dailySummaries': [
              {'records': List.generate(value, (_) => {})}
            ]
          },
        _ => {'totalSessions': value},
      };
      gate.complete(ResponseBody.fromString(
          jsonEncode(status == 200 ? data : {'code': 'TOKEN_EXPIRED'}), status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          }));
    }
  }

  @override
  void close({bool force = false}) {}
}

WorkoutRecordModel _record({bool known = true}) => WorkoutRecordModel.fromJson({
      'id': known ? 'native' : 'legacy',
      'date': DateTime.now().toIso8601String(),
      'targetSets': 3,
      'totalReps': 12,
      'poseMetricsSummary': known
          ? WorkoutEvidence.nativeSummary(
              completedReps: 12,
              recordedWarningEvents: 0,
              sets: [
                  {'reps': 12, 'weightKg': 0, 'badCount': 0}
                ])
          : {},
    });

void main() {
  for (final change in ['account', 'notifier']) {
    test('dashboard immediately withholds prior data on $change replacement',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final f = await sessionFixture(prefs);
      final service = _Dashboard(ApiClient(baseUrl: 'http://test'));
      final owner = StateProvider<AuthNotifier>((ref) => f.auth);
      final container = ProviderContainer(overrides: [
        authNotifierProvider.overrideWith((ref) => ref.watch(owner)),
        dashboardServiceProvider.overrideWithValue(service),
        workoutRecordsProvider
            .overrideWith((ref) => WorkoutRecordsNotifier(_Repo())),
      ]);
      addTearDown(container.dispose);
      container.listen(dashboardSummaryProvider, (_, __) {});
      await container.pump();
      for (var i = 0; i < 4; i++) {
        for (final call in service.calls.where((c) => !c.isCompleted)) {
          call.complete(_summary(77));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(
          container
              .read(dashboardSummaryProvider)
              .valueOrNull
              ?.todayCompletedSets,
          77);
      if (change == 'account') {
        await f.auth.login('B', 'password');
      } else {
        final replacement = await sessionFixture(prefs);
        // Same uid in a fresh notifier/login lifetime must not reuse the old aggregate.
        expect(replacement.auth.currentUser!.id, f.auth.currentUser!.id);
        container.read(owner.notifier).state = replacement.auth;
      }
      expect(container.read(dashboardSummaryProvider).valueOrNull, isNull);
    });
  }
  for (final oldStatus in [200, 401]) {
    test('aggregate families hide A during B pending, stale status $oldStatus',
        () async {
      SharedPreferences.setMockInitialValues({});
      final f = await sessionFixture(await SharedPreferences.getInstance());
      final server = _AggregateServer();
      final api = ApiClient(baseUrl: 'http://test')..setAuthToken('token-A');
      api.dio.httpClientAdapter = server;
      final container = ProviderContainer(overrides: [
        authNotifierProvider.overrideWith((ref) => f.auth),
        apiClientProvider.overrideWithValue(api),
        workoutRecordsProvider
            .overrideWith((ref) => WorkoutRecordsNotifier(_Repo())),
      ]);
      addTearDown(container.dispose);
      final month = monthlyCalendarProvider(DateTime(2026, 11));
      container.listen(dashboardSummaryProvider, (_, __) {});
      container.listen(month, (_, __) {});
      container.listen(serverReportCountsProvider, (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.pump();
      for (var i = 0; i < 4; i++) {
        server.finish('A', 7);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await container.pump();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.pump();
      expect(
          container.read(dashboardSummaryProvider).valueOrNull?.todayTotalReps,
          7);
      expect(container.read(month).valueOrNull?.recordCount, 7);
      expect(
          container.read(serverReportCountsProvider).valueOrNull?.totalSessions,
          7);
      // An ordinary same-session record refresh may retain that same owner's data.
      await container.read(workoutRecordsProvider.notifier).loadRecords();
      expect(
          container.read(dashboardSummaryProvider).valueOrNull?.todayTotalReps,
          7);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.pump();
      await f.auth.login('B', 'password');
      api.setAuthToken('token-B');
      expect(container.read(dashboardSummaryProvider).valueOrNull, isNull);
      expect(container.read(month).valueOrNull, isNull);
      expect(container.read(serverReportCountsProvider).valueOrNull, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.pump();
      final callsBeforeOldResponse = server.tokens.length;
      server.finish('A', 99, status: oldStatus);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.pump();
      expect(server.tokens.length,
          callsBeforeOldResponse); // No A request replayed with B's token.
      for (var i = 0; i < 4; i++) {
        server.finish('B', 2);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await container.pump();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.pump();
      expect(
          container.read(dashboardSummaryProvider).valueOrNull?.todayTotalReps,
          2);
      expect(container.read(month).valueOrNull?.recordCount, 2);
      expect(
          container.read(serverReportCountsProvider).valueOrNull?.totalSessions,
          2);
      await f.auth.logout();
      expect(container.read(dashboardSummaryProvider).valueOrNull, isNull);
      expect(container.read(month).valueOrNull, isNull);
      expect(container.read(serverReportCountsProvider).valueOrNull, isNull);
    });
  }
  for (final scenario in [
    'offline_partial',
    'old_server',
    'mixed_legacy',
    'empty',
    'versioned',
    'versioned_unknown'
  ]) {
    test('today actual-set fallback: $scenario', () {
      final records = scenario == 'empty'
          ? <WorkoutRecordModel>[]
          : [_record(), if (scenario == 'mixed_legacy') _record(known: false)];
      final wire = <String, dynamic>{
        'date': DateTime.now().toIso8601String(),
        'todayCompletedSets': 3,
        'todayTotalReps': records.length * 12,
        if (scenario.startsWith('versioned')) 'completedSetsEvidenceVersion': 1
      };
      if (scenario == 'versioned_unknown') wire['todayCompletedSets'] = null;
      final summary =
          scenario.startsWith('versioned') || scenario == 'old_server'
              ? DashboardSummary.fromJson(wire)
              : null;
      final container = ProviderContainer(overrides: [
        allRecordsProvider.overrideWithValue(records),
        dashboardSummaryProvider.overrideWithValue(AsyncValue.data(summary)),
      ]);
      addTearDown(container.dispose);
      final actual = container.read(todaySummaryProvider)['completedSets'];
      expect(
          actual,
          switch (scenario) {
            'empty' => 0,
            'mixed_legacy' || 'versioned_unknown' => null,
            'versioned' => 3,
            _ => 1
          });
      expect(container.read(todaySummaryProvider)['totalReps'],
          records.length * 12);
    });
  }
  testWidgets('home actual-set tile distinguishes unknown from a known zero',
      (tester) async {
    for (final sets in <int?>[null, 0]) {
      await tester.pumpWidget(ProviderScope(overrides: [
        currentUserProvider.overrideWithValue(sessionUser('synthetic')),
        todaySummaryProvider.overrideWithValue(
            {'completedSets': sets, 'totalMinutes': 0, 'totalReps': 0}),
        recentRecordsProvider.overrideWithValue([]),
        allRecordsProvider.overrideWithValue([]),
        weeklyWorkoutsProvider.overrideWithValue(0),
        daysSinceLastBodyCheckProvider.overrideWithValue(0),
      ], child: const MaterialApp(home: HomeScreen())));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('완료 세트'), findsOneWidget);
      expect(find.text(sets == null ? '—세트' : '0세트', findRichText: true),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
