import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/features/onboarding/services/calibration_result_store.dart';
import 'package:bpt/features/workout/data/motion_observer_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/session_fixture.dart';

Map<String, dynamic> calibration({bool includeStub = true}) => {
      'schemaVersion': 1,
      if (includeStub) 'stub': false,
      'bodyModel': 'smpl_neutral_v1.1.0',
      'smplBeta': List.filled(10, .1),
      'boneLengthData': {
        'unit': 'cm',
        'skeleton': 'h36m17',
        'pose': 'rest',
        'segments': {
          'left_hip-left_knee': 40.0,
          'left_knee-left_ankle': 40.0,
          'right_hip-right_knee': 42.0,
          'right_knee-right_ankle': 38.0,
          'left_shoulder-left_elbow': 30.0,
          'left_elbow-left_wrist': 24.0,
        },
        'appDefinitionDiffers': ['left_shoulder-left_elbow']
      },
      'quality': {
        'heightErrorCm': .3,
        'perView': {
          'front': {'reprojectionErrorPx': 4.2}
        }
      },
    };
const declaration = MotionProfileDeclaration(
    'job-A', .4, 'explicit per-profile engineering test declaration');

class DelayedStore extends CalibrationResultStore {
  DelayedStore(AuthNotifier owner) : super.forSession(owner.captureSession());
  final pending = Completer<Map<String, dynamic>?>();
  final loaded = Completer<void>();
  @override
  Future<Map<String, dynamic>?> load() {
    if (!loaded.isCompleted) loaded.complete();
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'same-owner current session forwards original validated segments and explicit weight',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final f = await sessionFixture(prefs);
    addTearDown(f.auth.dispose);
    final store = CalibrationResultStore.forSession(f.auth.captureSession());
    expect(await store.save('job-A', calibration()), isTrue);
    final loaded = await store.load();
    expect(loaded!['stub'], false);
    final calls = <Map<String, dynamic>>[];
    final bridge = MotionObserverProfileBridge(
        declaration: declaration,
        invoke: (method, args) async {
          calls.add({'method': method, ...args});
          return {'accepted': true};
        });
    await bridge.bind(store);
    expect(calls.map((c) => c['method']),
        ['beginMotionObserverProfileBinding', 'setMotionObserverProfile']);
    final profile = calls.last['profile'] as Map;
    expect(profile['scope'], 'same_account_live_camera_assumption');
    expect(profile['engineeringWeight']['value'], .4);
    expect(profile['calibration']['boneLengthData'], loaded['boneLengthData']);
    expect(profile.containsKey('ownerId'), isFalse);
  });
  test(
      'legacy unknown nonstub, unknown quality and undeclared weights stay withheld',
      () {
    for (final entry
        in <(Map<String, dynamic>, MotionProfileDeclaration?, String)>[
      (
        {...calibration(includeStub: false), 'ownerId': 'A', 'jobId': 'job-A'},
        declaration,
        'non_stub_provenance_unverified'
      ),
      (
        {...calibration(), 'ownerId': 'A', 'jobId': 'job-A', 'quality': {}},
        declaration,
        'quality_evidence_missing'
      ),
      (
        {...calibration(), 'ownerId': 'A', 'jobId': 'job-A'},
        null,
        'per_profile_weight_declaration_missing'
      ),
      (
        {...calibration(), 'ownerId': 'B', 'jobId': 'job-A'},
        declaration,
        'owner_or_result_missing'
      ),
    ]) {
      final result = MotionProfileAssessment.assess(entry.$1,
          ownerId: 'A', declaration: entry.$2);
      expect(result.payload, isNull);
      expect(result.reason, entry.$3);
    }
  });
  test('old async account result cannot overwrite replacement B binding',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final f = await sessionFixture(prefs);
    addTearDown(f.auth.dispose);
    final old = DelayedStore(f.auth);
    final calls = <Map<String, dynamic>>[];
    final bridge = MotionObserverProfileBridge(
        declaration: declaration,
        invoke: (method, args) async {
          calls.add({'method': method, ...args});
          return {'accepted': true};
        });
    final first = bridge.bind(old);
    await old.loaded.future;
    await f.auth.logout();
    await f.auth.login('B', 'password');
    final next = CalibrationResultStore.forSession(f.auth.captureSession());
    await next.save('job-A', calibration());
    await bridge.bind(next);
    old.pending.complete({...calibration(), 'ownerId': 'A', 'jobId': 'job-A'});
    await first;
    final sets =
        calls.where((c) => c['method'] == 'setMotionObserverProfile').toList();
    expect(sets, hasLength(1));
    expect(
        sets.single['binding'],
        calls
            .where((c) => c['method'] == 'beginMotionObserverProfileBinding')
            .last['binding']);
  });
  test(
      'same-owner relogin invalidates in-flight profile and disposal clears native binding',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final f = await sessionFixture(prefs);
    addTearDown(f.auth.dispose);
    final old = DelayedStore(f.auth);
    final calls = <Map<String, dynamic>>[];
    final bridge = MotionObserverProfileBridge(
        declaration: declaration,
        invoke: (method, args) async {
          calls.add({'method': method, ...args});
          return {'accepted': true};
        });
    final first = bridge.bind(old);
    await old.loaded.future;
    await f.auth.logout();
    await f.auth.login('A', 'password');
    bridge.dispose();
    old.pending.complete({...calibration(), 'ownerId': 'A', 'jobId': 'job-A'});
    await first;
    expect(
        calls.where((c) => c['method'] == 'setMotionObserverProfile'), isEmpty);
    expect(calls.last['binding'], startsWith('cleared-'));
  });
  test('native video/disabled rejection prevents reading account profile',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final f = await sessionFixture(prefs);
    addTearDown(f.auth.dispose);
    final store = DelayedStore(f.auth);
    final bridge = MotionObserverProfileBridge(
        declaration: declaration,
        invoke: (_, __) async =>
            {'accepted': false, 'reason': 'recorded_video_profile_forbidden'});
    await bridge.bind(store);
    expect(store.loaded.isCompleted, isFalse);
  });
  test('blank identity and job declaration do not satisfy account provenance',
      () {
    final result = MotionProfileAssessment.assess(
        {...calibration(), 'ownerId': '', 'jobId': ''},
        ownerId: '',
        declaration: const MotionProfileDeclaration('', .4, 'explicit'));
    expect(result.payload, isNull);
  });
  final legacyRoot = Platform.environment['BPT_EXISTING_SMPL_METADATA_DIR'];
  test(
      'existing legacy RGB-SMPL metadata remains rejected without account/job provenance',
      () {
    for (final name in ['P1.json', 'P2.json', 'P3.json']) {
      final data =
          (jsonDecode(File('$legacyRoot/$name').readAsStringSync()) as Map)
              .cast<String, dynamic>();
      expect(data.containsKey('boneLengthData'), isTrue);
      expect(data.containsKey('ownerId'), isFalse);
      expect(data.containsKey('jobId'), isFalse);
      expect(data.containsKey('smplBeta'), isFalse);
      expect(
          MotionProfileAssessment.assess(data,
                  ownerId: 'unavailable-current-owner', declaration: null)
              .payload,
          isNull);
    }
  }, skip: legacyRoot == null);
  test(
      'delayed start acknowledgement cannot bind after end, replacement or account change',
      () async {
    for (final reason in ['end', 'replacement', 'account']) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final f = await sessionFixture(prefs);
      final store = CalibrationResultStore.forSession(f.auth.captureSession());
      await store.save('job-A', calibration());
      final calls = <String>[];
      final bridge = MotionObserverProfileBridge(
          declaration: declaration,
          invoke: (method, args) async {
            calls.add(method);
            return {'accepted': true};
          });
      final started = Completer<void>();
      var current = true;
      final pending = bridge.bindAfterStart(started.future, store,
          stillCurrent: () => current);
      if (reason == 'end') bridge.cancelPendingStart();
      if (reason == 'replacement') current = false;
      if (reason == 'account') {
        await f.auth.logout();
        await f.auth.login('B', 'password');
      }
      started.complete();
      await pending;
      expect(calls, isEmpty, reason: reason);
      f.auth.dispose();
    }
  });
}
