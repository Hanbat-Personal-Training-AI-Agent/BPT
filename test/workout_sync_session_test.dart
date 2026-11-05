import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:bpt/services/local_storage_service.dart';
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

class _Server implements HttpClientAdapter {
  final calls = <(String, String?)>[];
  final Future<ResponseBody> Function(RequestOptions) handle;
  _Server(this.handle);
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancelFuture) {
    calls.add((
      (options.data as Map)['clientRecordId'] as String,
      options.headers['Authorization'] as String?
    ));
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody response(RequestOptions o, {int status = 200, String? code}) =>
    ResponseBody.fromString(
        jsonEncode(status == 200
            ? {
                'success': true,
                'clientRecordId': (o.data as Map)['clientRecordId'],
                'serverRecordId': 'server'
              }
            : {
                'error': {'code': code, 'message': 'synthetic failure'}
              }),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
WorkoutMetadataRequestDto dto(String id) => WorkoutMetadataRequestDto(
    clientRecordId: id,
    exerciseId: 'squat',
    exerciseName: 'Squat',
    date: DateTime(2026, 11, 2),
    totalReps: 1,
    correctReps: 0,
    incorrectReps: 0,
    durationSeconds: 1,
    postureScore: null,
    feedbackNotes: []);

class _BlockingRename extends SyncQueueStorage {
  _BlockingRename(super.prefs, super.uid);
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> replace(String id, WorkoutMetadataRequestDto value) async {
    await super.replace(id, value);
    entered.complete();
    await release.future;
  }
}

void main() {
  late SharedPreferences prefs;
  late AuthNotifier auth;
  late LocalStorageService local;
  late ApiClient activeApi;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final fixture = await sessionFixture(prefs);
    auth = fixture.auth;
    local = fixture.storage;
  });
  tearDown(() => auth.dispose());
  WorkoutSyncNotifier sync(_Server server, SyncQueueStorage queue) {
    final lease = auth.captureSession()!;
    final api = ApiClient(baseUrl: 'http://test')..setAuthToken('token-A');
    activeApi = api;
    api.dio.httpClientAdapter = server;
    final notifier = WorkoutSyncNotifier(api, queue, local, _Online(),
        isCurrentAccount: () => lease.isCurrent);
    addTearDown(notifier.dispose);
    return notifier;
  }

  Future<void> seed(SyncQueueStorage q, List<String> ids) async {
    for (final id in ids) {
      await q.enqueue(dto(id));
      await local.addRecord(WorkoutRecordModel.fromDto(dto(id)), uid: 'A');
    }
  }

  test(
      'switch during renumber stops retry and A-B-A cannot revive the old lease',
      () async {
    final q = _BlockingRename(prefs, 'A');
    await seed(q, ['taken']);
    final server = _Server((o) async =>
        response(o, status: 403, code: ApiClient.sessionAccessDenied));
    final notifier = sync(server, q);
    final pending = notifier.syncPendingRecords();
    await q.entered.future;
    await auth.login('B', 'password');
    activeApi.setAuthToken('token-B');
    q.release.complete();
    expect(await pending, false);
    expect(server.calls, [('taken', 'Bearer token-A')]);
    expect(q.getQueue(), hasLength(1));
    expect(q.getQueue().single.clientRecordId, isNot('taken'));
    expect(local.loadRecords(uid: 'A').single.id,
        q.getQueue().single.clientRecordId);
    expect(local.loadRecords(uid: 'B'), isEmpty);
    await auth.login('A', 'password');
    activeApi.setAuthToken('token-A');
    expect(await notifier.syncPendingRecords(), false);
    expect(server.calls, hasLength(1));
  });
  test('late acknowledgement after switch does not dequeue or mark synced',
      () async {
    final q = SyncQueueStorage(prefs, 'A');
    await seed(q, ['pending']);
    final entered = Completer<void>(), release = Completer<void>();
    final server = _Server((o) async {
      entered.complete();
      await release.future;
      return response(o);
    });
    final notifier = sync(server, q);
    final pending = notifier.syncPendingRecords();
    await entered.future;
    await auth.login('B', 'password');
    activeApi.setAuthToken('token-B');
    release.complete();
    expect(await pending, false);
    expect(q.getQueue(), hasLength(1));
    expect(local.loadRecords(uid: 'A').single.isSynced, false);
    expect(local.loadRecords(uid: 'B'), isEmpty);
  });
  test('concurrent triggers share one drain and one post per queued row',
      () async {
    final q = SyncQueueStorage(prefs, 'A');
    await seed(q, ['one']);
    final entered = Completer<void>(), release = Completer<void>();
    final server = _Server((o) async {
      entered.complete();
      await release.future;
      return response(o);
    });
    final notifier = sync(server, q);
    final one = notifier.syncPendingRecords();
    await entered.future;
    final two = notifier.syncPendingRecords();
    expect(identical(one, two), true);
    release.complete();
    expect(await one, true);
    expect(await two, true);
    expect(server.calls, hasLength(1));
    expect(q.getQueue(), isEmpty);
    expect(local.loadRecords(uid: 'A').single.isSynced, true);
  });
  test(
      'permanent400 stays visible and persisted while a following healthy row syncs',
      () async {
    final q = SyncQueueStorage(prefs, 'A');
    await seed(q, ['bad', 'good']);
    final original = q.getQueue().first.toJson();
    final other = SyncQueueStorage(prefs, 'A_errors');
    await other.enqueue(dto('other-owner'));
    final server = _Server((o) async => response(o,
        status: (o.data as Map)['clientRecordId'] == 'bad' ? 400 : 200,
        code: 'INVALID_INPUT_VALUE'));
    final notifier = sync(server, q);
    expect(await notifier.syncPendingRecords(), false);
    expect(server.calls.map((x) => x.$1), ['bad', 'good']);
    expect(q.getQueue().single.toJson(), original);
    expect(notifier.state.value!.recordErrors['bad'],
        contains('400/INVALID_INPUT_VALUE'));
    expect(SyncQueueStorage(prefs, 'A').getFailures()['bad'], isNotEmpty);
    expect(other.getQueue().single.clientRecordId, 'other-owner');
    final restored = sync(server, SyncQueueStorage(prefs, 'A'));
    expect(restored.state.value!.recordErrors['bad'],
        contains('400/INVALID_INPUT_VALUE'));
    expect(restored.state.value!.lastSyncError, isNotNull);
    expect(
        local.loadRecords(uid: 'A').singleWhere((r) => r.id == 'good').isSynced,
        true);
    expect(
        local.loadRecords(uid: 'A').singleWhere((r) => r.id == 'bad').isSynced,
        false);
  });
  test('network failure stops the run and retains all following records',
      () async {
    final q = SyncQueueStorage(prefs, 'A');
    await seed(q, ['offline', 'later']);
    final server = _Server((o) async => throw DioException.connectionError(
        requestOptions: o, reason: 'offline'));
    final notifier = sync(server, q);
    expect(await notifier.syncPendingRecords(), false);
    expect(server.calls.map((x) => x.$1), ['offline']);
    expect(q.getQueue(), hasLength(2));
    expect(q.getFailures(), isEmpty);
    expect(notifier.state.value!.lastSyncError, isNotNull);
  });

  test(
      'old-token401 cannot replay a queued mutation under the new account token',
      () async {
    final q = SyncQueueStorage(prefs, 'A');
    await seed(q, ['old-token']);
    final entered = Completer<void>(), release = Completer<void>();
    final server = _Server((o) async {
      entered.complete();
      await release.future;
      return response(o, status: 401, code: 'TOKEN_EXPIRED');
    });
    final notifier = sync(server, q);
    final pending = notifier.syncPendingRecords();
    await entered.future;
    await auth.login('B', 'password');
    activeApi.setAuthToken('token-B');
    release.complete();
    expect(await pending, false);
    expect(server.calls, [('old-token', 'Bearer token-A')]);
    expect(q.getQueue(), hasLength(1));
    expect(local.loadRecords(uid: 'B'), isEmpty);
  });
}
