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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// 서버 대신 응답한다. [taken] 번호는 다른 계정 기록이라 403을 준다.
class _FakeServer implements HttpClientAdapter {
  final taken = <String>{'taken'};
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options.path);
    var status = 200;
    Object body = const <Object>[];
    if (options.path == '/workouts/records/sync') {
      final id = (options.data as Map)['clientRecordId'] as String;
      if (taken.contains(id)) {
        status = 403;
        body = {
          'success': false,
          'error': {
            'code': ApiClient.sessionAccessDenied,
            'message': '본인의 운동 데이터만 접근할 수 있습니다.'
          }
        };
      } else {
        body = {'serverRecordId': 'server-$id', 'clientRecordId': id};
      }
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
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
      date: DateTime(2026, 10, 18),
      totalReps: 10,
      correctReps: 10,
      incorrectReps: 0,
      durationSeconds: 60,
      postureScore: 90,
      feedbackNotes: const [],
    );

void main() {
  test('new record ids are random UUIDs', () {
    final ids = List.generate(100, (_) => newClientRecordId());
    expect(ids.toSet(), hasLength(100));
    for (final id in ids) {
      expect(
          id,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    }
  });

  test('id taken by another account is renumbered and the queue keeps going',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final server = _FakeServer();
    final refresh = _FakeServer();
    final api = ApiClient(
        baseUrl: 'http://test',
        refreshDio: Dio(BaseOptions(baseUrl: 'http://test'))
          ..httpClientAdapter = refresh)
      ..setAuthToken('access')
      ..setRefreshToken('refresh');
    api.dio.httpClientAdapter = server;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWithValue(api),
      connectivityProvider.overrideWithValue(_FakeConnectivity()),
      currentUserIdProvider.overrideWithValue('A'),
    ]);
    addTearDown(container.dispose);

    final storage = LocalStorageService(prefs);
    final queue = container.read(syncQueueStorageProvider)!;
    for (final id in ['taken', 'next']) {
      await queue.enqueue(_dto(id));
      await storage.addRecord(
          WorkoutRecordModel.fromDto(_dto(id), isSynced: false),
          uid: 'A');
    }

    final done =
        await container.read(workoutSyncProvider.notifier).syncPendingRecords();

    expect(done, isTrue);
    expect(queue.getQueue(), isEmpty);
    // 403은 토큰 만료가 아니므로 토큰을 갱신하지 않는다.
    expect(refresh.requests, isEmpty);
    final records = storage.loadRecords(uid: 'A');
    expect(records.map((r) => r.id), isNot(contains('taken')));
    expect(records.every((r) => r.isSynced), isTrue);
    expect(records.map((r) => r.id), contains('next'));
  });
}
