import 'dart:async';
import 'dart:convert';

import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/features/onboarding/services/calibration_result_store.dart';
import 'package:bpt/features/onboarding/services/calibration_upload_service.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/session_fixture.dart';

Map<String, dynamic> measurement([double hip = 28]) => {
      'userHeightCm': 170,
      'smplBeta': List.filled(10, 0.1),
      'boneLengthData': {
        'unit': 'cm',
        'skeleton': 'h36m17',
        'pose': 'rest',
        'segments': {'hip_width': hip, 'shoulder_width': 30.0},
        'appDefinitionDiffers': ['hip_width']
      },
      'quality': {
        'heightErrorCm': -.3,
        'perView': {
          'front': {'reprojectionErrorPx': 4.2}
        }
      },
      'modelGlbUrl': 'https://storage.example.test/private',
      'debug': {'secret': true},
    };

class _PendingJob extends CalibrationUploadService {
  _PendingJob()
      : super(
            config: const CalibrationUploadConfig(),
            tokenProvider: () async => 'token');
  final response = Completer<CalibrationJob>();
  @override
  Future<CalibrationJob> fetchJob(String id, {dynamic cancelToken}) =>
      response.future;
}

class _SlowClear extends LocalStorageService {
  _SlowClear(super.prefs);
  final clear = Completer<void>();
  @override
  Future<void> clearSession() async {
    await clear.future;
    await super.clearSession();
  }
}

class _SlowSave extends LocalStorageService {
  _SlowSave(super.prefs);
  Completer<void>? hold;
  @override
  Future<void> saveUser(UserModel user) async {
    final pending = hold;
    hold = null;
    if (pending != null) await pending.future;
    await super.saveUser(user);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('session writers in unrelated prefs stores do not block or share state',
      () async {
    final first = LocalStorageService(await SharedPreferences.getInstance());
    final held = Completer<void>();
    final old = first.serializeSessionWrite(() => held.future);
    SharedPreferences.setMockInitialValues({});
    final second = LocalStorageService(await SharedPreferences.getInstance());
    var ran = false;
    await second.serializeSessionWrite(() async {
      ran = true;
    });
    expect(ran, isTrue);
    held.complete();
    await old;
  });

  test('recreated notifier persists B after an already-started A clear',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final oldStorage = _SlowClear(prefs);
    final oldAuth = AuthNotifier(SessionAuthService(), oldStorage);
    await oldAuth.login('A', 'password');
    final logout = oldAuth.logout();
    await Future<void>.delayed(Duration.zero);
    oldAuth.dispose();
    final storage = LocalStorageService(prefs);
    final replacement = AuthNotifier(SessionAuthService(), storage);
    addTearDown(replacement.dispose);
    final login = replacement.login('B', 'password', rememberMe: true);
    await Future<void>.delayed(Duration.zero);
    oldStorage.clear.complete();
    await logout;
    await login;
    expect(storage.loadUser()!.id, 'B');
    expect(storage.loadAuthToken(), 'token-B');
    expect(storage.loadAutoLogin(), isTrue);
  });

  test('recreated notifier persists B after an already-started A profile save',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final oldStorage = _SlowSave(prefs), service = SessionAuthService();
    final oldAuth = AuthNotifier(service, oldStorage);
    await oldAuth.login('A', 'password');
    final held = Completer<void>();
    oldStorage.hold = held;
    final saved =
        oldAuth.updateProfile(sessionUser('A').copyWith(name: 'late A'));
    await Future<void>.delayed(Duration.zero);
    oldAuth.dispose();
    final storage = LocalStorageService(prefs);
    final replacement = AuthNotifier(SessionAuthService(), storage);
    addTearDown(replacement.dispose);
    final login = replacement.login('B', 'password', rememberMe: true);
    await Future<void>.delayed(Duration.zero);
    held.complete();
    await saved;
    await login;
    expect(storage.loadUser()!.id, 'B');
    expect(storage.loadAuthToken(), 'token-B');
    expect(service.profileWrites, isEmpty);
  });

  test(
      'an active profile response with a different owner invalidates a mismatched cached session',
      () async {
    final f = await sessionFixture(await SharedPreferences.getInstance());
    addTearDown(f.auth.dispose);
    f.service.profile = Completer();
    final pending = f.auth.tryAutoLogin();
    f.service.profile!.complete(sessionUser('B'));
    expect(await pending, isFalse);
    expect(f.auth.currentUser, isNull);
    expect(f.storage.loadAuthToken(), isNull);
    expect(f.storage.loadAutoLogin(), isFalse);
  });

  for (final onboarding in [false, true]) {
    test(
        'account switch during ${onboarding ? 'onboarding' : 'profile'} persistence prevents an A-data PUT with B token',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SessionAuthService();
      final storage = _SlowSave(prefs);
      final auth = AuthNotifier(service, storage);
      addTearDown(auth.dispose);
      await auth.login('A', 'password');
      final held = Completer<void>();
      storage.hold = held;
      final pending = onboarding
          ? auth.saveOnboarding(
              gender: 'female',
              heightCm: 170,
              weightKg: 60,
              workoutGoal: 'health',
              weeklyFrequency: 3)
          : auth.updateProfile(sessionUser('A').copyWith(name: 'edited A'));
      await Future<void>.delayed(Duration.zero);
      final logout = auth.logout();
      final login = auth.login('B', 'password');
      await Future<void>.delayed(Duration.zero);
      held.complete();
      await pending;
      await logout;
      await login;
      expect(service.profileWrites, isEmpty);
      expect(service.onboardingWrites, isEmpty);
      expect(auth.currentUser!.id, 'B');
      expect(storage.loadUser()!.id, 'B');
    });
  }

  test(
      'late A deletion completion does not clear B session or persisted profile',
      () async {
    final f = await sessionFixture(await SharedPreferences.getInstance());
    addTearDown(f.auth.dispose);
    f.service.deletion = Completer<void>();
    final pending = f.auth.deleteAccount();
    await f.auth.logout();
    await f.auth.login('B', 'password', rememberMe: true);
    f.service.deletion!.complete();
    await pending;
    expect(f.auth.currentUser!.id, 'B');
    expect(f.storage.loadUser()!.id, 'B');
    expect(f.storage.loadAuthToken(), 'token-B');
    expect(f.storage.loadAutoLogin(), isTrue);
  });

  test(
      'logout invalidates scan before awaiting clearSession, without resurrecting A',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final service = SessionAuthService();
    final storage = _SlowClear(prefs);
    final auth = AuthNotifier(service, storage);
    addTearDown(auth.dispose);
    await auth.login('A', 'password');
    final lease = auth.captureSession()!;
    service.scan = Completer();
    final scan = auth.recordBodyScan();
    final logout = auth.logout();
    expect(auth.currentUser, isNull);
    expect(lease.isCurrent, isFalse);
    service.scan!.complete(
        sessionUser('A').copyWith(lastBodyScanDate: DateTime(2026, 11, 2)));
    await scan;
    expect(auth.currentUser, isNull);
    expect(storage.loadUser()!.lastBodyScanDate, isNull);
    storage.clear.complete();
    await logout;
  });

  test(
      'delayed old clear finishes before the new account credentials are persisted',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final service = SessionAuthService();
    final storage = _SlowClear(prefs);
    final auth = AuthNotifier(service, storage);
    addTearDown(auth.dispose);
    await auth.login('A', 'password');
    final logout = auth.logout();
    await Future<void>.delayed(Duration.zero);
    final login = auth.login('B', 'password', rememberMe: true);
    await Future<void>.delayed(Duration.zero);
    storage.clear.complete();
    await logout;
    await login;
    expect(auth.currentUser!.id, 'B');
    expect(storage.loadUser()!.id, 'B');
    expect(storage.loadAuthToken(), 'token-B');
    expect(storage.loadAutoLogin(), isTrue);
  });

  test(
      'A to B to A rejects old success and old failure from the first A session',
      () async {
    final f = await sessionFixture(await SharedPreferences.getInstance());
    addTearDown(f.auth.dispose);
    f.service.scan = Completer();
    final old = f.auth.recordBodyScan();
    final lease = f.auth.captureSession()!;
    await f.auth.logout();
    await f.auth.login('B', 'password');
    await f.auth.logout();
    await f.auth.login('A', 'password');
    f.service.scan!.completeError(NetworkException());
    await old;
    expect(lease.isCurrent, isFalse);
    expect(f.auth.currentUser!.id, 'A');
    expect(f.auth.currentUser!.lastBodyScanDate, isNull);
    expect(f.storage.loadUser()!.lastBodyScanDate, isNull);
  });

  for (final unauthorized in [false, true]) {
    test(
        'late auto-login profile ${unauthorized ? '401' : 'success'} cannot overwrite or log out B',
        () async {
      final f = await sessionFixture(await SharedPreferences.getInstance());
      addTearDown(f.auth.dispose);
      f.service.profile = Completer();
      final pending = f.auth.tryAutoLogin();
      await f.auth.logout();
      await f.auth.login('B', 'password');
      if (unauthorized) {
        f.service.profile!.completeError(UnauthorizedException());
      } else {
        f.service.profile!.complete(sessionUser('A'));
      }
      expect(await pending, isFalse);
      expect(f.auth.currentUser!.id, 'B');
      expect(f.storage.loadUser()!.id, 'B');
    });
  }

  test(
      'result/reference accounts are separate; unowned legacy remains untouched',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        CalibrationResultStore.resultKey, jsonEncode(measurement(99)));
    final legacyRef =
        CalibrationResultStore.referenceKey('squat', 'back_squat');
    await prefs.setString(legacyRef, '{"feet_width":99}');
    final f = await sessionFixture(prefs);
    addTearDown(f.auth.dispose);
    final a = CalibrationResultStore.forSession(f.auth.captureSession());
    expect(await a.load(), isNull);
    expect(await a.loadReference('squat', 'back_squat'), isEmpty);
    expect(await a.save('job-A', measurement()), isTrue);
    await a.saveReference('squat', 'back_squat', {'feet_width': 1.4});
    final saved = (await a.load())!;
    expect(saved['ownerId'], 'A');
    expect(saved.containsKey('modelGlbUrl'), isFalse);
    expect(saved.containsKey('debug'), isFalse);
    expect(saved['qualityAvailable'], isTrue);
    expect(saved['quality'], measurement()['quality']);
    expect((saved['boneLengthData'] as Map)['appDefinitionDiffers'],
        ['hip_width']);
    await f.auth.logout();
    await f.auth.login('B', 'password');
    final b = CalibrationResultStore.forSession(f.auth.captureSession());
    expect(await b.load(), isNull);
    expect(await b.loadReference('squat', 'back_squat'), isEmpty);
    expect(await a.save('late-A', measurement(50)), isFalse);
    expect(await a.saveReference('squat', 'back_squat', {'feet_width': 3}),
        isFalse);
    await b.save('job-B', measurement(35));
    await b.saveReference('squat', 'back_squat', {'feet_width': 1.8});
    await f.auth.logout();
    await f.auth.login('A', 'password');
    final restored = CalibrationResultStore.forSession(f.auth.captureSession());
    expect((await restored.load())!['jobId'], 'job-A');
    expect(await restored.loadReference('squat', 'back_squat'),
        {'feet_width': 1.4});
    expect(prefs.getString(legacyRef), '{"feet_width":99}');
    expect(
        jsonDecode(
            prefs.getString(CalibrationResultStore.resultKey)!)['userHeightCm'],
        170);
  });

  test(
      'bad units, body types, NaN/Infinity and invalid beta are rejected without overwriting',
      () async {
    final f = await sessionFixture(await SharedPreferences.getInstance());
    addTearDown(f.auth.dispose);
    final store = CalibrationResultStore.forSession(f.auth.captureSession());
    await store.save('valid', measurement());
    final bad = [
      {...measurement(), 'boneLengthData': 'not an object'},
      {
        ...measurement(),
        'boneLengthData': {
          'unit': 'm',
          'segments': {'hip_width': .28}
        }
      },
      {
        ...measurement(),
        'boneLengthData': {
          'unit': 'cm',
          'segments': {'hip_width': '28'}
        }
      },
      {...measurement(), 'userHeightCm': double.nan},
      {...measurement(), 'userHeightCm': double.infinity},
      {
        ...measurement(),
        'smplBeta': [double.nan, ...List.filled(9, 0)]
      },
    ];
    for (final value in bad) {
      expect(await store.save('bad', value), isFalse);
      expect(CalibrationResultStore.bodyProfileFrom(value), isNull);
    }
    expect((await store.load())!['jobId'], 'valid');
    expect(
        await store
            .saveReference('squat', 'bodyweight', {'feet_width': double.nan}),
        isFalse);
  });

  test('same identity token refresh preserves lease; disposal invalidates it',
      () async {
    final f = await sessionFixture(await SharedPreferences.getInstance());
    final lease = f.auth.captureSession()!;
    f.service.restoreAuthToken('new-access', refreshToken: 'new-refresh');
    expect(lease.isCurrent, isTrue);
    final store = CalibrationResultStore.forSession(lease);
    expect(await store.save('fresh-token-result', measurement()), isTrue);
    f.auth.dispose();
    expect(lease.isCurrent, isFalse);
    expect(await store.load(), isNull);
  });

  test('missing or entirely unknown quality never becomes available', () async {
    final f = await sessionFixture(await SharedPreferences.getInstance());
    addTearDown(f.auth.dispose);
    final store = CalibrationResultStore.forSession(f.auth.captureSession());
    final absent = measurement()..remove('quality');
    await store.save('unknown', absent);
    expect((await store.load())!['qualityAvailable'], isFalse);
    await store.save('unknown', {
      ...absent,
      'quality': {
        'heightErrorCm': null,
        'perView': {
          'front': {'reprojectionErrorPx': null}
        },
      }
    });
    expect((await store.load())!['qualityAvailable'], isFalse);
  });

  test(
      'provider replaces account stores, while ordinary same-session updates retain them',
      () async {
    final f = await sessionFixture(await SharedPreferences.getInstance());
    final container = ProviderContainer(
        overrides: [authNotifierProvider.overrideWith((ref) => f.auth)]);
    addTearDown(container.dispose);
    final subscription =
        container.listen(calibrationResultStoreProvider, (_, __) {});
    addTearDown(subscription.close);
    final a = container.read(calibrationResultStoreProvider);
    await f.auth.recordBodyScan();
    expect(
        identical(a, container.read(calibrationResultStoreProvider)), isTrue);
    await f.auth.logout();
    await f.auth.login('B', 'password');
    final b = container.read(calibrationResultStoreProvider);
    expect(a.isCurrent, isFalse);
    expect(b.ownerId, 'B');
    expect(identical(a, b), isFalse);
    await f.auth.logout();
    await f.auth.login('A', 'password');
    expect(a.isCurrent, isFalse);
    expect(container.read(calibrationResultStoreProvider).isCurrent, isTrue);
  });

  test(
      'same-id notifier replacement gets a unique identity and a live replacement store',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final first = await sessionFixture(prefs),
        replacement = await sessionFixture(prefs);
    var active = first.auth;
    final container = ProviderContainer(
        overrides: [authNotifierProvider.overrideWith((ref) => active)]);
    addTearDown(container.dispose);
    final subscription =
        container.listen(calibrationResultStoreProvider, (_, __) {});
    addTearDown(subscription.close);
    final old = container.read(calibrationResultStoreProvider);
    final identity = container.read(authSessionIdentityProvider);
    active = replacement.auth;
    container.invalidate(authNotifierProvider);
    final fresh = container.read(calibrationResultStoreProvider);
    expect(old.isCurrent, isFalse);
    expect(fresh.isCurrent, isTrue);
    expect(fresh.ownerId, 'A');
    expect(container.read(authSessionIdentityProvider), isNot(identity));
    expect(await fresh.save('new-owner-lifetime', measurement()), isTrue);
  });

  test('late tracked done job cannot save into B or new A session', () async {
    final prefs = await SharedPreferences.getInstance();
    final f = await sessionFixture(prefs);
    addTearDown(f.auth.dispose);
    final store = CalibrationResultStore.forSession(f.auth.captureSession());
    final service = _PendingJob();
    addTearDown(service.close);
    final pending = store.track(service, 'old-job', interval: Duration.zero);
    await f.auth.logout();
    await f.auth.login('B', 'password');
    await f.auth.logout();
    await f.auth.login('A', 'password');
    service.response
        .complete(CalibrationJob('done', 100, result: measurement()));
    await pending;
    expect(prefs.containsKey(CalibrationResultStore.accountResultKey('A')),
        isFalse);
    expect(prefs.containsKey(CalibrationResultStore.accountResultKey('B')),
        isFalse);
  }, skip: !CalibrationResultStore.enabled);
}
