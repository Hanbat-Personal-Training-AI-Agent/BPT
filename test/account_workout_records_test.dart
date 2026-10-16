import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:bpt/services/sync_service.dart';
import 'package:bpt/services/workout_records_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConnectivity implements Connectivity {
  bool online = false;
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [online ? ConnectivityResult.wifi : ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}

/// 서버 대신 응답한다. 기록 전송은 어떤 토큰으로 왔는지 남긴다.
/// 오프라인이면 연결 오류를 낸다.
class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.connectivity);
  final _FakeConnectivity connectivity;
  final synced = <(String?, String)>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (!connectivity.online) {
      throw DioException.connectionError(
          requestOptions: options, reason: 'offline');
    }
    Object body = const <Object>[];
    if (options.path == '/workouts/records/sync') {
      final id = (options.data as Map)['clientRecordId'] as String;
      synced.add((options.headers['Authorization'] as String?, id));
      body = {'serverRecordId': 'server-$id', 'clientRecordId': id};
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

WorkoutMetadataRequestDto _dto(String id) => WorkoutMetadataRequestDto(
      clientRecordId: id,
      exerciseId: 'squat',
      exerciseName: 'Squat',
      date: DateTime(2026, 10, 16),
      totalReps: 10,
      correctReps: 10,
      incorrectReps: 0,
      durationSeconds: 60,
      postureScore: 90,
      feedbackNotes: const [],
    );

void main() {
  late ProviderContainer container;
  late _FakeConnectivity connectivity;
  late _FakeServer server;
  late ApiClient api;
  final uid = StateProvider<String?>((_) => null);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    connectivity = _FakeConnectivity();
    server = _FakeServer(connectivity);
    api = ApiClient(baseUrl: 'http://test');
    api.dio.httpClientAdapter = server;
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWithValue(api),
      connectivityProvider.overrideWithValue(connectivity),
      currentUserIdProvider.overrideWith((ref) => ref.watch(uid)),
    ]);
  });

  tearDown(() => container.dispose());

  /// 계정을 바꾸고 그 계정의 기록을 다 불러올 때까지 기다린다.
  Future<List<String>> loginAs(String? user) async {
    container.read(uid.notifier).state = user;
    api.setAuthToken(user == null ? null : 'token-$user');
    container.read(workoutRecordsProvider); // 기록 불러오기 시작
    await container.read(workoutRecordsProvider.notifier).loadRecords();
    return [
      for (final r in container.read(workoutRecordsProvider).value ?? []) r.id
    ];
  }

  test('offline record of A is never shown to or sent as B', () async {
    await loginAs('A');
    await container
        .read(workoutRecordsProvider.notifier)
        .addMetadataRecord(_dto('a-1'));
    await pumpEventQueue(); // 저장 직후 시도한 전송이 (오프라인이라) 실패할 때까지
    expect(await loginAs('A'), ['a-1']);

    // 로그아웃 → B 로그인 → 네트워크 복구
    expect(await loginAs(null), isEmpty);
    connectivity.online = true;
    expect(await loginAs('B'), isEmpty);
    await container.read(workoutSyncProvider.notifier).syncPendingRecords();
    expect(server.synced, isEmpty);

    // A로 다시 로그인하면 A의 기록만, A의 토큰으로 보낸다.
    expect(await loginAs('A'), ['a-1']);
    await container.read(workoutSyncProvider.notifier).syncPendingRecords();
    expect(server.synced, [('Bearer token-A', 'a-1')]);
  });

  test('legacy shared cache and queue are not given to any account', () async {
    SharedPreferences.setMockInitialValues({
      'bpt_workout_records': '[]',
      LocalStorageService.legacySyncQueueKey:
          jsonEncode([_dto('old').toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    await LocalStorageService(prefs).removeLegacyRecords();
    expect(prefs.getKeys(), isEmpty);
  });
}
