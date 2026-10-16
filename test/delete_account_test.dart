import 'dart:convert';
import 'dart:typed_data';

import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/services/auth_service.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 로그인은 성공시키고, 탈퇴(DELETE /users/me)는 [deleteStatus]로 응답한다.
class _FakeServer implements HttpClientAdapter {
  int deleteStatus = 500;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final (status, body) = switch (options.path) {
      '/auth/login' => (
          200,
          {
            'token': 'access',
            'user': {'id': '7', 'username': 'kori', 'email': 'k@bpt.dev'},
          }
        ),
      _ => (deleteStatus, <String, Object>{}),
    };
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late SharedPreferences prefs;
  late _FakeServer server;
  late AuthNotifier auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'bpt_workout_records_7': '[]',
      LocalStorageService.syncQueueKey('7'): '[]',
      'bpt_workout_records_other': '[]',
    });
    prefs = await SharedPreferences.getInstance();
    server = _FakeServer();
    final api = ApiClient(baseUrl: 'http://test');
    api.dio.httpClientAdapter = server;
    auth = AuthNotifier(AuthService(api), LocalStorageService(prefs));
    await auth.login('kori', 'password');
    expect(auth.isLoggedIn, isTrue);
  });

  test('failed delete keeps the user signed in and their data', () async {
    final error = await auth.deleteAccount();
    expect(error, isNotNull);
    expect(auth.isLoggedIn, isTrue);
    expect(prefs.containsKey('bpt_workout_records_7'), isTrue);
    expect(prefs.containsKey('bpt_user'), isTrue);
  });

  test('successful delete removes only that account\'s local data', () async {
    server.deleteStatus = 200;
    expect(await auth.deleteAccount(), isNull);
    expect(auth.isLoggedIn, isFalse);
    expect(prefs.getKeys(), {'bpt_workout_records_other', 'bpt_auto_login'});
  });
}
