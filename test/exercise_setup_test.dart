import 'package:bpt/features/onboarding/services/calibration_result_store.dart';
import 'package:bpt/features/workout/data/native_pose_channel.dart';
import 'package:bpt/features/workout/widgets/exercise_setup_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _payload({String phase = 'holding', List<Map<String, Object?>>? items, Map<String, double>? snapshot}) => {
      'rep': 0,
      'setup': {
        'exercise': 'squat',
        'phase': phase,
        'progress': 0.4,
        'moving': false,
        'items': items ??
            [
              {'key': 'feet_width', 'value': 1.42, 'quality': 'good', 'required': true, 'depth': 0.12},
              {'key': 'torso_incline', 'value': 8.0, 'quality': 'low', 'required': true, 'depth': 0.0},
              {'key': 'feet_width_shoulder', 'quality': 'missing', 'required': false, 'depth': 0.0},
            ],
        if (snapshot != null) 'snapshot': snapshot,
      },
    };

Widget _panel(NativeSetupStatus? status, {bool hasReference = false}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExerciseSetupPanel(
            isKo: true,
            exerciseId: 'squat',
            exerciseName: '스쿼트',
            status: status,
            hasReference: hasReference,
            bodyProfile: const {'hipWidthCm': 28.4, 'shoulderWidthCm': 31.0},
            onReset: () {},
            onSaveReference: () {},
          ),
        ),
      ),
    );

void main() {
  test('setup channel names and payload parse (experimental, absent without the flag payload)', () {
    expect([NativePoseChannel.resetSetup, NativePoseChannel.setSetupVariant], ['resetSetup', 'setSetupVariant']);
    final s = NativeSetupStatus.parse(_payload())!;
    expect(s.phase, 'holding');
    expect(s.exercise, 'squat');
    expect(s.items.map((i) => i.key), ['feet_width', 'torso_incline', 'feet_width_shoulder']);
    expect(s.items[0].measured, isTrue);
    expect(s.items[1].measured, isFalse, reason: 'low confidence: no number');
    expect(s.items[2].value, isNull);
    expect(NativeSetupStatus.parse({'rep': 1}), isNull);
    expect(NativeSetupStatus.parse({'setup': {'items': []}}), isNull, reason: 'phase is required');
    final ready = NativeSetupStatus.parse(_payload(phase: 'ready', snapshot: {'feet_width': 1.4}))!;
    expect(ready.isReady, isTrue);
    expect(ready.snapshot, {'feet_width': 1.4});
  });

  testWidgets('panel: ratios only for observed items, no cue without a saved reference, save only when ready',
      (tester) async {
    await tester.pumpWidget(_panel(NativeSetupStatus.parse(_payload())));
    expect(find.textContaining('골반 너비의 1.4배'), findsOneWidget);
    expect(find.textContaining('측정 중'), findsNWidgets(2));
    expect(find.textContaining('8°'), findsNothing, reason: 'low-quality torso tilt shows no number');
    expect(find.textContaining('넓혀'), findsNothing);
    expect(find.textContaining('체형 측정(관절 중심)'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('setup_save'))).onPressed, isNull);

    await tester.pumpWidget(_panel(NativeSetupStatus.parse(_payload(phase: 'ready', snapshot: {'feet_width': 1.42}))));
    expect(find.textContaining('올바른 자세라는 판정은 아니에요'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('setup_save'))).onPressed, isNotNull);
  });

  testWidgets('panel: cue comes only from the saved personal reference', (tester) async {
    final items = [
      {'key': 'feet_width', 'value': 1.1, 'quality': 'good', 'required': true, 'depth': 0.1, 'ref': 1.4, 'cue': 'increase'},
      {'key': 'torso_incline', 'value': 6.0, 'quality': 'good', 'required': true, 'depth': 0.0, 'ref': 6.5, 'cue': null},
    ];
    await tester.pumpWidget(_panel(NativeSetupStatus.parse(_payload(items: items)), hasReference: true));
    expect(find.text('양발 간격을 조금 넓혀 주세요'), findsOneWidget);
    expect(find.textContaining('상체가'), findsNothing, reason: 'within tolerance: no cue');
    expect(ExerciseSetupPanel.valueText(NativeSetupItem.parse({'key': 'grip_width', 'value': 1.5, 'quality': 'good', 'approx': true})!, isKo: true),
        '어깨 너비의 1.5배');
    expect(ExerciseSetupPanel.qualityText(NativeSetupItem.parse({'key': 'feet_width', 'value': 1.2, 'quality': 'depth_estimated'})!, isKo: true),
        '측면이라 추정치');
  });

  test('calibration result -> body profile (joint-centre cm, L/R averaged) and personal references', () async {
    expect(CalibrationResultStore.bodyProfileFrom(null), isNull);
    expect(CalibrationResultStore.bodyProfileFrom({'boneLengthData': {'segments': {'right_hip-right_knee': 44.0}}}), isNull);
    final p = CalibrationResultStore.bodyProfileFrom({
      'userHeightCm': 170,
      'boneLengthData': {
        'segments': {
          'hip_width': 28.0, 'shoulder_width': 30.0,
          'right_hip-right_knee': 44.0, 'left_hip-left_knee': 46.0,
          'right_knee-right_ankle': 42.0, 'left_knee-left_ankle': 42.0,
          'right_shoulder-right_elbow': 26.0, 'left_shoulder-left_elbow': 27.0,
          'right_elbow-right_wrist': 24.0,
        },
      },
    })!;
    expect(p, {
      'hipWidthCm': 28.0, 'shoulderWidthCm': 30.0, 'thighCm': 45.0, 'shinCm': 42.0,
      'upperArmCm': 26.5, 'forearmCm': 24.0, 'heightCm': 170.0,
    });

    SharedPreferences.setMockInitialValues({});
    final store = CalibrationResultStore.instance;
    expect(await store.loadReference('squat', 'bodyweight'), isEmpty);
    await store.saveReference('squat', 'back_squat', {'feet_width': 1.4});
    expect(await store.loadReference('squat', 'back_squat'), {'feet_width': 1.4});
    expect(await store.loadReference('squat', 'bodyweight'), isEmpty, reason: 'per variant');
    await store.save('job-1', {'userHeightCm': 170, 'smplBeta': [0.1], 'boneLengthData': {'segments': {'hip_width': 28.0}}, 'modelGlbUrl': 'https://x'});
    final saved = (await store.load())!;
    expect(saved.containsKey('modelGlbUrl'), isFalse, reason: 'expiring signed URL is not stored');
    expect((await store.bodyProfile())!['hipWidthCm'], 28.0);
  });
}
