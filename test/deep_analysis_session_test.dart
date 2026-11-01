import 'dart:async';
import 'dart:io';

import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/features/workout/data/deep_analysis_service.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deep_analysis_service_test.dart' show Adapter, config, json;
import 'helpers/session_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'provider keeps ordinary refresh but rejects old A callbacks after A-B-A',
      () async {
    final f = await sessionFixture(await SharedPreferences.getInstance());
    final refresh =
        Adapter((_, __) async => json({'accessToken': 'must-not-run'}));
    final api = ApiClient(
        baseUrl: 'https://spring.example',
        refreshDio: Dio()..httpClientAdapter = refresh)
      ..setAuthToken('A-token')
      ..setRefreshToken('A-refresh');
    final container = ProviderContainer(overrides: [
      authNotifierProvider.overrideWith((ref) => f.auth),
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final subscription =
        container.listen(deepAnalysisServiceProvider, (_, __) {});
    addTearDown(subscription.close);
    final old = container.read(deepAnalysisServiceProvider);
    await old.saveQueue([
      {'sessionId': 'set-A', 'jobId': 'accepted-A', 'status': 'queued'}
    ]);
    await f.auth.recordBodyScan();
    api.setAuthToken('A-refreshed');
    expect(identical(container.read(deepAnalysisServiceProvider), old), isTrue);
    expect(await old.tokenProvider(), 'A-refreshed');
    await f.auth.logout();
    await f.auth.login('B', 'password');
    await f.auth.logout();
    await f.auth.login('A', 'password');
    expect(await old.tokenProvider(), isNull);
    expect(await old.refreshToken!('A-refreshed'), isNull);
    expect(await old.loadQueue(), isEmpty);
    await old.saveQueue([]);
    final fresh = container.read(deepAnalysisServiceProvider);
    expect(fresh.isCurrent, isTrue);
    expect(identical(old, fresh), isFalse);
    expect((await fresh.loadQueue()).single['jobId'], 'accepted-A');
  });

  test(
      'same-id notifier recreation invalidates provider token and refresh callbacks',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final first = await sessionFixture(prefs),
        second = await sessionFixture(prefs);
    var active = first.auth;
    final api = ApiClient()..setAuthToken('A-token');
    final container = ProviderContainer(overrides: [
      authNotifierProvider.overrideWith((ref) => active),
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final subscription =
        container.listen(deepAnalysisServiceProvider, (_, __) {});
    addTearDown(subscription.close);
    final old = container.read(deepAnalysisServiceProvider);
    active = second.auth;
    container.invalidate(authNotifierProvider);
    final fresh = container.read(deepAnalysisServiceProvider);
    expect(await old.tokenProvider(), isNull);
    expect(await old.refreshToken!('A-token'), isNull);
    expect(fresh.isCurrent, isTrue);
    expect(fresh.userId, 'A');
  });

  test(
      'late queue read and queued write cannot erase accepted rows from a new A lifetime',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final f = await sessionFixture(prefs);
    addTearDown(f.auth.dispose);
    final lease = f.auth.captureSession()!;
    final old = DeepAnalysisService(
        config: config,
        tokenProvider: () async => 'A',
        userId: 'A',
        sessionGuard: () => lease.isCurrent);
    addTearDown(old.close);
    await old.saveQueue([
      {'sessionId': 'set-A', 'jobId': 'accepted-A', 'status': 'queued'}
    ]);
    final held = Completer<void>();
    final writer =
        LocalStorageService(prefs).serializeSessionWrite(() => held.future);
    final write = old.saveQueue([]), read = old.loadQueue();
    final logout = f.auth.logout();
    held.complete();
    await writer;
    await write;
    await logout;
    expect(await read, isEmpty);
    await f.auth.login('A', 'password');
    final freshLease = f.auth.captureSession()!;
    final fresh = DeepAnalysisService(
        config: config,
        tokenProvider: () async => 'A',
        userId: 'A',
        sessionGuard: () => freshLease.isCurrent);
    addTearDown(fresh.close);
    expect((await fresh.loadQueue()).single['jobId'], 'accepted-A');
  });

  for (final status in [200, 401]) {
    test('generic request preserves the epoch guard inside refresh ($status)',
        () async {
      var epoch = 1, saves = 0, expired = 0, requests = 0;
      final started = Completer<void>(), response = Completer<ResponseBody>();
      final refresh = Dio()
        ..httpClientAdapter = Adapter((_, __) {
          started.complete();
          return response.future;
        });
      final api = ApiClient(refreshDio: refresh)
        ..setAuthToken('A')
        ..setRefreshToken('A-refresh');
      api.onTokensRefreshed = (_, __) => saves++;
      api.onSessionExpired = () => expired++;
      api.dio.httpClientAdapter = Adapter((_, __) async {
        requests++;
        return ResponseBody.fromString('{}', 401);
      });
      final pending = api.post('/users/me/body-scan',
          data: {'fixture': 'A'},
          options:
              Options(extra: {ApiClient.sessionGuardKey: () => epoch == 1}));
      await started.future;
      epoch = 3;
      api.setAuthToken('A');
      api.setRefreshToken('A-refresh');
      response.complete(status == 200
          ? json({'accessToken': 'late-A'})
          : ResponseBody.fromString('{}', 401));
      await expectLater(
          pending,
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', ApiClient.sessionChangedCode)));
      expect(api.authToken, 'A');
      expect(api.refreshToken, 'A-refresh');
      expect(saves, 0);
      expect(expired, 0);
      expect(requests, 1);
    });

    test('stale initiating refresh cannot poison a new valid epoch ($status)',
        () async {
      var epoch = 1, refreshes = 0, saves = 0, expired = 0;
      final oldStarted = Completer<void>(), newStarted = Completer<void>();
      final oldReply = Completer<ResponseBody>(),
          newReply = Completer<ResponseBody>();
      final refresh = Dio()
        ..httpClientAdapter = Adapter((_, __) {
          refreshes++;
          if (refreshes == 1) {
            oldStarted.complete();
            return oldReply.future;
          }
          if (refreshes == 2) {
            newStarted.complete();
            return newReply.future;
          }
          throw StateError('same epoch did not share the new refresh');
        });
      final api = ApiClient(refreshDio: refresh)
        ..setAuthToken('A')
        ..setRefreshToken('A-refresh');
      api.onTokensRefreshed = (_, __) => saves++;
      api.onSessionExpired = () => expired++;
      final old = api.refreshAccessToken('A', sessionGuard: () => epoch == 1);
      await oldStarted.future;
      epoch = 3;
      final current =
          api.refreshAccessToken('A', sessionGuard: () => epoch == 3);
      await newStarted.future.timeout(const Duration(seconds: 2));
      oldReply.complete(status == 200
          ? json({'accessToken': 'old-result'})
          : ResponseBody.fromString('{}', 401));
      expect(await old, isNull);
      final joined =
          api.refreshAccessToken('A', sessionGuard: () => epoch == 3);
      await Future<void>.delayed(Duration.zero);
      expect(refreshes, 2);
      newReply.complete(
          json({'accessToken': 'fresh-A', 'refreshToken': 'fresh-A-refresh'}));
      expect(await Future.wait([current, joined]), ['fresh-A', 'fresh-A']);
      expect(api.authToken, 'fresh-A');
      expect(saves, 1);
      expect(expired, 0);
    });

    test(
        'same credential strings cannot authorize a stale epoch refresh ($status)',
        () async {
      var epoch = 1;
      var saved = 0;
      var expired = 0;
      final started = Completer<void>(), response = Completer<ResponseBody>();
      final refresh = Dio()
        ..httpClientAdapter = Adapter((_, __) {
          started.complete();
          return response.future;
        });
      final api = ApiClient(refreshDio: refresh)
        ..setAuthToken('A')
        ..setRefreshToken('A-refresh');
      api.onTokensRefreshed = (_, __) => saved++;
      api.onSessionExpired = () => expired++;
      final pending =
          api.refreshAccessToken('A', sessionGuard: () => epoch == 1);
      await started.future;
      epoch = 3;
      // Same uid/token bytes, but a different login lifetime.
      api.setAuthToken('A');
      api.setRefreshToken('A-refresh');
      response.complete(status == 200
          ? json({'accessToken': 'late-A', 'refreshToken': 'late-refresh'})
          : ResponseBody.fromString('{}', 401));
      expect(await pending, isNull);
      expect(api.authToken, 'A');
      expect(api.refreshToken, 'A-refresh');
      expect(saved, 0);
      expect(expired, 0);
    });
  }

  test('same-epoch guarded requests retain single-flight refresh', () async {
    var refreshes = 0, requests = 0;
    final refresh = Dio()
      ..httpClientAdapter = Adapter((_, __) async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return json(
            {'accessToken': 'fresh-A', 'refreshToken': 'fresh-A-refresh'});
      });
    final api = ApiClient(refreshDio: refresh)
      ..setAuthToken('A')
      ..setRefreshToken('A-refresh');
    api.dio.httpClientAdapter = Adapter((o, __) async {
      requests++;
      return o.headers['Authorization'] == 'Bearer fresh-A'
          ? json({'ok': true})
          : ResponseBody.fromString('{}', 401);
    });
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        api.post('/users/me/body-scan',
            options: Options(extra: {ApiClient.sessionGuardKey: () => true}))
    ]);
    expect(results, hasLength(2));
    expect(refreshes, 1);
    expect(requests, 4);
  });

  test('late same-uid 401 does not refresh or resend an old service request',
      () async {
    var epoch = 1;
    var refreshes = 0;
    var requests = 0;
    final started = Completer<void>(), response = Completer<ResponseBody>();
    final service = DeepAnalysisService(
        config: config,
        tokenProvider: () async => 'A',
        userId: 'A',
        sessionGuard: () => epoch == 1,
        refreshToken: (_) async {
          refreshes++;
          return 'new-A';
        },
        api: Dio()
          ..httpClientAdapter = Adapter((_, __) {
            requests++;
            started.complete();
            return response.future;
          }));
    addTearDown(service.close);
    final pending = service.fetchJob('accepted-A', CancelToken());
    await started.future;
    epoch = 3;
    response.complete(ResponseBody.fromString('{}', 401));
    await expectLater(pending, throwsA(isA<DioException>()));
    expect(requests, 1);
    expect(refreshes, 0);
  });

  test(
      'accepted old upload can be recovered idempotently by the next owned lifetime',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('bpt-owned-synthetic-');
    addTearDown(() => directory.delete(recursive: true));
    final video =
        await File('${directory.path}/synthetic.mp4').writeAsBytes([1, 2, 3]);
    final capture = DeepAnalysisCapture(video.path, {
      'schemaVersion': 1,
      'sessionId': 'set-A',
      'exerciseId': 'squat',
      'reps': []
    });
    var epoch = 1;
    final started = Completer<void>(), accepted = Completer<ResponseBody>();
    final old = DeepAnalysisService(
        config: config,
        tokenProvider: () async => 'A',
        userId: 'A',
        sessionGuard: () => epoch == 1,
        api: Dio()
          ..httpClientAdapter = Adapter((_, __) {
            started.complete();
            return accepted.future;
          }));
    addTearDown(old.close);
    final pending = old.upload(capture, CancelToken());
    await started.future;
    epoch = 3;
    accepted.complete(json({'status': 'accepted', 'jobId': 'accepted-A'}));
    await expectLater(pending, throwsA(isA<DioException>()));
    var requests = 0;
    final fresh = DeepAnalysisService(
        config: config,
        tokenProvider: () async => 'new-A',
        userId: 'A',
        sessionGuard: () => epoch == 3,
        api: Dio()
          ..httpClientAdapter = Adapter((request, _) async {
            requests++;
            expect((request.data as Map)['clientSessionId'], 'set-A');
            return json({'status': 'accepted', 'jobId': 'accepted-A'});
          }));
    addTearDown(fresh.close);
    expect(await fresh.upload(capture, CancelToken()), 'accepted-A');
    expect(requests, 1);
    expect(await video.exists(), isTrue);
  });
}
