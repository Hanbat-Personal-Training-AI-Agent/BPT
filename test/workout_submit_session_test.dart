import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/data/repositories/workout_repository.dart';
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

class _IdempotentServer implements HttpClientAdapter {
  final entered = Completer<void>(), release = Completer<void>();
  final rows = <(String, String), Map<String, dynamic>>{};
  final writes = <(String, String)>[];
  bool first = true;
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final token = o.headers['Authorization'] as String;
    if (o.method == 'GET') {
      return _json(
          rows.entries
              .where((e) => e.key.$1 == token)
              .map((e) => e.value)
              .toList(),
          200);
    }
    final data = Map<String, dynamic>.from(o.data as Map),
        id = data['clientRecordId'] as String;
    writes.add((token, id));
    rows.putIfAbsent((token, id), () => {...data, 'id': 'server-one'});
    if (first) {
      first = false;
      entered.complete();
      await release.future;
      return _json({
        'error': {
          'code': 'TOKEN_EXPIRED',
          'message': 'synthetic lost acknowledgement'
        }
      }, 401);
    }
    return _json(
        {'success': true, 'clientRecordId': id, 'serverRecordId': 'server-one'},
        200);
  }

  ResponseBody _json(Object value, int code) =>
      ResponseBody.fromString(jsonEncode(value), code, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
  @override
  void close({bool force = false}) {}
}

void main() {
  test(
      'staged A submit survives a lost acknowledgement and same-owner retry is one record',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final f = await sessionFixture(prefs);
    addTearDown(f.auth.dispose);
    final server = _IdempotentServer();
    final refresh = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server;
    final api = ApiClient(baseUrl: 'http://test', refreshDio: refresh)
      ..setAuthToken('token-A');
    api.dio.httpClientAdapter = server;
    final q = SyncQueueStorage(prefs, 'A'), online = _Online();
    final lease = f.auth.captureSession()!;
    final sync = WorkoutSyncNotifier(api, q, f.storage, online,
        isCurrentAccount: () => lease.isCurrent);
    addTearDown(sync.dispose);
    final repo = WorkoutRepository(api, f.storage, q, sync, online,
        isCurrentAccount: () => lease.isCurrent);
    final dto = WorkoutMetadataRequestDto(
        clientRecordId: 'unknown-ack',
        exerciseId: 'squat',
        exerciseName: 'Squat',
        date: DateTime(2026, 11, 2),
        totalReps: 1,
        correctReps: 0,
        incorrectReps: 0,
        durationSeconds: 1,
        postureScore: null,
        feedbackNotes: []);
    final pending = repo.submitWorkoutRecord(dto);
    await server.entered.future;
    expect(q.getQueue().single.clientRecordId, dto.clientRecordId);
    expect(f.storage.loadRecords(uid: 'A').single.isSynced, false);
    await f.auth.login('B', 'password');
    api.setAuthToken('token-B');
    server.release.complete();
    expect((await pending).isSynced, false);
    expect(server.writes, [('Bearer token-A', dto.clientRecordId)]);
    expect(q.getQueue(), hasLength(1));
    expect(f.storage.loadRecords(uid: 'B'), isEmpty);
    await f.auth.login('A', 'password');
    api.setAuthToken('token-A');
    expect(await repo.getWorkoutRecords(), isEmpty,
        reason: 'A-B-A does not revive an old request lease');
    final fresh = f.auth.captureSession()!;
    final newSync = WorkoutSyncNotifier(api, q, f.storage, online,
        isCurrentAccount: () => fresh.isCurrent);
    addTearDown(newSync.dispose);
    final newRepo = WorkoutRepository(api, f.storage, q, newSync, online,
        isCurrentAccount: () => fresh.isCurrent);
    expect(await newRepo.getWorkoutRecords(), hasLength(1),
        reason: 'accepted server row and staged local row are one ID');
    expect(await newSync.syncPendingRecords(), true);
    expect(server.rows, hasLength(1));
    expect(server.writes, hasLength(2));
    expect(server.writes.every((w) => w.$1 == 'Bearer token-A'), true);
    expect(q.getQueue(), isEmpty);
    expect(f.storage.loadRecords(uid: 'A'), hasLength(1));
    expect(f.storage.loadRecords(uid: 'A').single.isSynced, true);
    expect(f.storage.loadRecords(uid: 'B'), isEmpty);
  });
}
