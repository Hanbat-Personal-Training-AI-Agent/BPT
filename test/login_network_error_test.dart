import 'dart:typed_data';

import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/services/auth_service.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 서버에 연결되지 않는 상황.
class _Unreachable implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      throw DioException.connectionError(
          requestOptions: options, reason: 'unreachable');

  @override
  void close({bool force = false}) {}
}

void main() {
  test('login does not sign in when the server is unreachable', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService(await SharedPreferences.getInstance());
    final api = ApiClient(baseUrl: 'http://test');
    api.dio.httpClientAdapter = _Unreachable();
    final auth = AuthNotifier(AuthService(api), storage);

    await auth.login('someone', 'password');

    expect(auth.isLoggedIn, isFalse);
    expect(auth.error, 'network_error');
    expect(storage.loadUser(), isNull);
  });
}
