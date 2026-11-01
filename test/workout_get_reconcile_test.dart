import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/data/repositories/workout_repository.dart';
import 'package:bpt/features/workout/data/workout_evidence.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:bpt/services/sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/session_fixture.dart';

class _Online implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _DelayedGet implements HttpClientAdapter {
  _DelayedGet(this.snapshot);
  final List<Map<String, dynamic>> snapshot;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    Object data;
    if (o.method == 'GET') {
      entered.complete();
      await release.future;
      data = snapshot;
    } else {
      data = {
        'clientRecordId': (o.data as Map)['clientRecordId'],
        'serverRecordId': 'server-one',
        'success': true
      };
    }
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

WorkoutMetadataRequestDto _dto() => WorkoutMetadataRequestDto(
    clientRecordId: 'concurrent',
    exerciseId: 'squat',
    exerciseName: 'Squat',
    date: DateTime(2026, 11, 2),
    totalReps: 1,
    correctReps: 0,
    incorrectReps: 0,
    durationSeconds: 1,
    postureScore: null,
    feedbackNotes: [],
    poseMetricsSummary: WorkoutEvidence.nativeSummary(
        completedReps: 1,
        recordedWarningEvents: 3,
        sets: [
          {'reps': 1, 'weightKg': 5, 'badCount': 3}
        ]));
void main() {
  for (final mode in [
    'new_ack_absent',
    'new_evidence_omitted',
    'old_pending_acked',
    'old_ack_with_newer_server'
  ]) {
    test('pending GET reconciles concurrent submit: $mode', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final f = await sessionFixture(prefs);
      addTearDown(f.auth.dispose);
      final dto = _dto();
      if (mode.startsWith('old_')) {
        await f.storage.addRecord(WorkoutRecordModel.fromDto(dto), uid: 'A');
      }
      final server = _DelayedGet(mode == 'old_ack_with_newer_server'
          ? [
              {
                ...dto.toJson(),
                'clientRecordId': 'newer',
                'id': 'server-newer',
                'date': '2026-11-03T12:00:00'
              }
            ]
          : mode == 'new_evidence_omitted'
              ? [
                  {
                    ...dto.toJson(),
                    'id': 'server-one',
                    'poseMetricsSummary': null
                  }
                ]
              : []);
      final api = ApiClient(baseUrl: 'http://test')..setAuthToken('token-A');
      api.dio.httpClientAdapter = server;
      final lease = f.auth.captureSession()!,
          q = SyncQueueStorage(prefs, 'A'),
          online = _Online();
      final sync = WorkoutSyncNotifier(api, q, f.storage, online,
          isCurrentAccount: () => lease.isCurrent);
      addTearDown(sync.dispose);
      final repo = WorkoutRepository(api, f.storage, q, sync, online,
          isCurrentAccount: () => lease.isCurrent);
      final get = repo.getWorkoutRecords();
      await server.entered.future;
      expect((await repo.submitWorkoutRecord(dto)).isSynced, true);
      server.release.complete();
      final result = await get;
      expect(result, hasLength(mode == 'old_ack_with_newer_server' ? 2 : 1));
      final submitted = result.singleWhere((r) => r.id == dto.clientRecordId);
      expect(submitted.isSynced, true);
      expect(submitted.poseMetricsSummary, dto.poseMetricsSummary);
      expect(
          f.storage
              .loadRecords(uid: 'A')
              .singleWhere((r) => r.id == dto.clientRecordId)
              .poseMetricsSummary,
          dto.poseMetricsSummary);
      if (mode == 'old_ack_with_newer_server') {
        expect(result.map((r) => r.id), ['newer', dto.clientRecordId]);
        expect(f.storage.loadRecords(uid: 'A').map((r) => r.id),
            ['newer', dto.clientRecordId]);
      }
      expect(q.getQueue(), isEmpty);
    });
  }
  test('an unchanged synced historical row missing from GET is not resurrected',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final f = await sessionFixture(prefs);
    addTearDown(f.auth.dispose);
    await f.storage.addRecord(
        WorkoutRecordModel.fromDto(_dto(),
            isSynced: true, serverId: 'server-one'),
        uid: 'A');
    final server = _DelayedGet([]),
        api = ApiClient(baseUrl: 'http://test')..setAuthToken('token-A');
    api.dio.httpClientAdapter = server;
    final lease = f.auth.captureSession()!,
        q = SyncQueueStorage(prefs, 'A'),
        online = _Online();
    final sync = WorkoutSyncNotifier(api, q, f.storage, online,
        isCurrentAccount: () => lease.isCurrent);
    addTearDown(sync.dispose);
    final repo = WorkoutRepository(api, f.storage, q, sync, online,
        isCurrentAccount: () => lease.isCurrent);
    final get = repo.getWorkoutRecords();
    await server.entered.future;
    server.release.complete();
    expect(await get, isEmpty);
    expect(f.storage.loadRecords(uid: 'A'), isEmpty);
  });
}
