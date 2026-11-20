import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/services/auth_service.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ResponseBody reply(Object value, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(value), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'direct AuthService login without a predicate retains its public behavior',
      () async {
    final api = ApiClient(baseUrl: 'https://api.example.test');
    api.dio.httpClientAdapter = _Adapter((_) async => reply({
          'token': 'direct',
          'refreshToken': 'direct-refresh',
          'user': {'id': 'direct'},
        }));
    final user =
        await AuthService(api).login(email: 'direct', password: 'secret');
    expect(user.id, 'direct');
    expect(api.authToken, 'direct');
    expect(api.refreshToken, 'direct-refresh');
  });

  for (final signup in [false, true]) {
    for (final lateFailure in [false, true]) {
      test(
          'late ${signup ? 'signup' : 'login'} A ${lateFailure ? 'failure' : 'success'} cannot commit over B',
          () async {
        final starts = {
          for (final id in ['A', 'B']) id: Completer<void>()
        };
        final responses = {
          for (final id in ['A', 'B']) id: Completer<ResponseBody>()
        };
        final adapter = _Adapter((o) {
          final id = (o.data as Map)['email'] as String;
          starts[id]!.complete();
          return responses[id]!.future;
        });
        final api = ApiClient(baseUrl: 'https://api.example.test');
        api.dio.httpClientAdapter = adapter;
        final storage =
            LocalStorageService(await SharedPreferences.getInstance());
        final auth = AuthNotifier(AuthService(api), storage);
        addTearDown(auth.dispose);
        final old = signup
            ? auth.signUp(
                username: 'A',
                email: 'A',
                password: 'secret',
                name: 'A',
                phoneNumber: '01012345678',
                birthDate: DateTime(2000))
            : auth.login('A', 'secret');
        await starts['A']!.future;
        final current = auth.login('B', 'secret', rememberMe: true);
        await starts['B']!.future;
        responses['B']!.complete(reply({
          'token': 'B-access',
          'refreshToken': 'B-refresh',
          'user': {'id': 'B'}
        }));
        await current;
        responses['A']!.complete(lateFailure
            ? reply({'message': 'rejected'}, 401)
            : reply({
                'token': 'A-access',
                'refreshToken': 'A-refresh',
                'user': {'id': 'A'}
              }, signup ? 201 : 200));
        await old;
        expect(auth.currentUser!.id, 'B');
        expect(auth.error, isNull);
        expect(api.authToken, 'B-access');
        expect(api.refreshToken, 'B-refresh');
        expect(storage.loadUser()!.id, 'B');
        expect(storage.loadAuthToken(), 'B-access');
        expect(storage.loadAutoLogin(), isTrue);
        for (final r in adapter.requests) {
          expect(r.headers.containsKey(ApiClient.sessionGuardKey), isFalse);
          expect(
              jsonEncode(r.data), isNot(contains(ApiClient.sessionGuardKey)));
        }
      });
    }
  }

  test(
      'logout while login is pending prevents service token commit and persistence',
      () async {
    final started = Completer<void>(), response = Completer<ResponseBody>();
    final api = ApiClient(baseUrl: 'https://api.example.test');
    api.dio.httpClientAdapter = _Adapter((_) {
      started.complete();
      return response.future;
    });
    final storage = LocalStorageService(await SharedPreferences.getInstance());
    final auth = AuthNotifier(AuthService(api), storage);
    addTearDown(auth.dispose);
    final pending = auth.login('A', 'password');
    await started.future;
    await auth.logout();
    response.complete(reply({
      'token': 'late-A',
      'refreshToken': 'late-A-refresh',
      'user': {'id': 'A'}
    }));
    await pending;
    expect(auth.currentUser, isNull);
    expect(api.authToken, isNull);
    expect(api.refreshToken, isNull);
    expect(storage.loadAuthToken(), isNull);
    expect(storage.loadUser(), isNull);
  });

  test(
      'stale request guard cancels before sending and fails closed on a throwing predicate',
      () async {
    final adapter = _Adapter((_) async => reply({'ok': true}));
    final api = ApiClient(baseUrl: 'https://api.example.test');
    api.dio.httpClientAdapter = adapter;
    for (final guard in <bool Function()>[
      () => false,
      () => throw StateError('disposed')
    ]) {
      await expectLater(
          api.post('/users/me/body-scan',
              data: {'private': 'A'},
              options: Options(extra: {ApiClient.sessionGuardKey: guard})),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', ApiClient.sessionChangedCode)));
    }
    expect(adapter.requests, isEmpty);
  });

  test('delayed A 401 cannot retry A mutation under B token', () async {
    var generation = 1;
    final started = Completer<void>(), response = Completer<ResponseBody>();
    final refresh = _Adapter((_) async => reply({'accessToken': 'unexpected'}));
    final refreshDio = Dio()..httpClientAdapter = refresh;
    final api =
        ApiClient(baseUrl: 'https://api.example.test', refreshDio: refreshDio)
          ..setAuthToken('A')
          ..setRefreshToken('A-refresh');
    final requests = _Adapter((_) {
      started.complete();
      return response.future;
    });
    api.dio.httpClientAdapter = requests;
    final pending = api.post('/users/me/body-scan',
        data: {'bodyScanLocalPath': 'A-local'},
        options:
            Options(extra: {ApiClient.sessionGuardKey: () => generation == 1}));
    await started.future;
    generation = 2;
    api.setAuthToken('B');
    api.setRefreshToken('B-refresh');
    response.complete(reply({'message': 'expired'}, 401));
    await expectLater(
        pending,
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', ApiClient.sessionChangedCode)));
    expect(requests.requests, hasLength(1));
    expect(refresh.requests, isEmpty);
    expect(api.authToken, 'B');
    expect(api.refreshToken, 'B-refresh');
  });

  test(
      'same-session token refresh still retries the guarded mutation successfully',
      () async {
    final refresh = _Adapter((_) async =>
        reply({'accessToken': 'new-A', 'refreshToken': 'new-A-refresh'}));
    final api = ApiClient(
        baseUrl: 'https://api.example.test',
        refreshDio: Dio()..httpClientAdapter = refresh)
      ..setAuthToken('old-A')
      ..setRefreshToken('old-A-refresh');
    final requests = _Adapter((o) async =>
        o.headers['Authorization'] == 'Bearer new-A'
            ? reply({'ok': true})
            : reply({'message': 'expired'}, 401));
    api.dio.httpClientAdapter = requests;
    final result = await api.post('/users/me/body-scan',
        data: {'private': 'A'},
        options: Options(extra: {ApiClient.sessionGuardKey: () => true}));
    expect(result.data, {'ok': true});
    expect(requests.requests, hasLength(2));
    expect(refresh.requests, hasLength(1));
    expect(api.authToken, 'new-A');
  });

  test('account change during refresh cancels instead of retrying with B',
      () async {
    var generation = 1;
    final started = Completer<void>(), response = Completer<ResponseBody>();
    final refresh = _Adapter((_) {
      started.complete();
      return response.future;
    });
    final api = ApiClient(
        baseUrl: 'https://api.example.test',
        refreshDio: Dio()..httpClientAdapter = refresh)
      ..setAuthToken('old-A')
      ..setRefreshToken('old-A-refresh');
    final requests = _Adapter((_) async => reply({'message': 'expired'}, 401));
    api.dio.httpClientAdapter = requests;
    final pending = api.post('/users/me/body-scan',
        data: {'private': 'A'},
        options:
            Options(extra: {ApiClient.sessionGuardKey: () => generation == 1}));
    await started.future;
    generation = 2;
    api.setAuthToken('B');
    api.setRefreshToken('B-refresh');
    response.complete(
        reply({'accessToken': 'late-A', 'refreshToken': 'late-A-refresh'}));
    await expectLater(
        pending,
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', ApiClient.sessionChangedCode)));
    expect(requests.requests, hasLength(1));
    expect(api.authToken, 'B');
    expect(api.refreshToken, 'B-refresh');
  });
}
