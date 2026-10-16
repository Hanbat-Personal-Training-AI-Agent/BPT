import 'dart:convert';
import 'dart:typed_data';

import 'package:bpt/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버 대신 응답하는 가짜 어댑터. 요청마다 [handler]가 (상태 코드, 본문)을 정한다.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final (int, Object) Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = handler(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _expired = {'timestamp': '', 'status': 403, 'error': 'Forbidden'};

void main() {
  late _FakeAdapter api;
  late _FakeAdapter refresh;
  late ApiClient client;

  /// [refreshStatus]: /auth/refresh 응답 코드. 200이면 new-access / new-refresh 를 준다.
  void prepare({int refreshStatus = 200}) {
    api = _FakeAdapter((o) => o.path.startsWith('/auth/')
        ? (401, {'success': false})
        : o.headers['Authorization'] == 'Bearer new-access'
            ? (200, {'id': 1})
            : (403, _expired));
    refresh = _FakeAdapter((o) => refreshStatus == 200
        ? (200, {'accessToken': 'new-access', 'refreshToken': 'new-refresh'})
        : (
            refreshStatus,
            {
              'success': false,
              'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'}
            }
          ));
    final refreshDio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = refresh;
    client = ApiClient(baseUrl: 'http://test', refreshDio: refreshDio)
      ..setAuthToken('old-access')
      ..setRefreshToken('old-refresh');
    client.dio.httpClientAdapter = api;
  }

  test('expired access token is refreshed once and the request retried',
      () async {
    prepare();
    final saved = <(String, String?)>[];
    client.onTokensRefreshed = (a, r) => saved.add((a, r));
    final results = await Future.wait(
        [client.get('/users/me'), client.get('/workouts/records')]);
    expect(results.map((r) => r.statusCode), [200, 200]);
    // 동시에 만료돼도 갱신 요청은 한 번만 간다.
    expect(refresh.requests, hasLength(1));
    expect(refresh.requests.single.data, {'refreshToken': 'old-refresh'});
    expect(saved, [('new-access', 'new-refresh')]);
    expect(client.authToken, 'new-access');
    expect(client.refreshToken, 'new-refresh');
  });

  test('rejected refresh token ends the session', () async {
    prepare(refreshStatus: 401);
    var expired = 0;
    client.onSessionExpired = () => expired++;
    await expectLater(
        client.get('/users/me'), throwsA(isA<UnauthorizedException>()));
    expect(expired, 1);
    expect(client.authToken, isNull);
    expect(client.refreshToken, isNull);
  });

  test('server error on refresh keeps the session', () async {
    prepare(refreshStatus: 500);
    var expired = 0;
    client.onSessionExpired = () => expired++;
    await expectLater(
        client.get('/users/me'), throwsA(isA<UnauthorizedException>()));
    expect(expired, 0);
    expect(client.refreshToken, 'old-refresh');
  });

  test('auth API 401 (wrong password) does not refresh', () async {
    prepare();
    await expectLater(client.post('/auth/login', data: {}),
        throwsA(isA<UnauthorizedException>()));
    expect(refresh.requests, isEmpty);
  });
}
