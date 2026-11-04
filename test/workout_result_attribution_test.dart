import 'dart:convert';

import 'package:bpt/core/i18n/locale_provider.dart';
import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/features/workout/data/workout_evidence.dart';
import 'package:bpt/features/workout/data/workout_result_evidence.dart';
import 'package:bpt/features/workout/screens/workout_result_screen.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:bpt/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> reopen(WorkoutRecordModel record) => {
      'isHistory': true,
      'totalReps': record.totalReps,
      'targetSets': record.targetSets,
      'targetReps': record.targetReps,
      'correctReps': record.correctReps,
      'incorrectReps': record.incorrectReps,
      ...record.resultEvidenceFields,
    };

void main() {
  late SharedPreferences prefs;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await (FontLoader('Pretendard')
          ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf')))
        .load();
  });

  Future<void> show(WidgetTester tester, Map<String, dynamic> result) async {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        selectedLanguageProvider.overrideWith((ref) => 'en'),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        home: WorkoutResultScreen(result: {'isHistory': true, ...result}),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
  }

  test('legacy goals and correctness fields cannot manufacture sets or weight',
      () {
    final raw = <String, dynamic>{
      'totalReps': 11,
      'targetSets': 3,
      'correctReps': 11,
      'postureScore': 100,
    };
    final original = jsonEncode(raw);
    final evidence = WorkoutResultEvidence.fromResult(raw);
    expect(evidence.sets, isEmpty);
    expect(evidence.completedSets, isNull);
    expect(evidence.volumeKg, isNull);
    expect(evidence.recordedWeightKg, isNull);
    expect(jsonEncode(raw), original);
  });

  test('known aggregates survive an unavailable set distribution', () {
    final evidence = WorkoutResultEvidence.fromResult({
      'totalReps': 11,
      'completedSets': 2,
      'targetSets': 5,
      'weightKg': 0,
      'totalVolume': 25,
    });
    expect(evidence.sets, isEmpty);
    expect(evidence.completedSets, 2);
    // Unversioned wire totalVolume may be an old estimate; retain raw input
    // without presenting it as observed set volume.
    expect(evidence.volumeKg, isNull);
    expect(evidence.recordedWeightKg, 0);
  });

  test('equal sets are real entries but duplicate explicit identities are not',
      () {
    final repeated = {'reps': 5, 'weightKg': 0, 'badCount': 4};
    final known = WorkoutResultEvidence.fromResult({
      'totalReps': 10,
      'setResults': [repeated, repeated],
    });
    expect(known.sets.map((set) => set.number), [1, 2]);
    expect(known.completedSets, 2);
    expect(known.volumeKg, 0);
    expect(known.sets.map((set) => set.warningEvents), [4, 4]);
    final duplicate = WorkoutResultEvidence.fromResult({
      'totalReps': 10,
      'setResults': [
        {...repeated, 'setNumber': 1},
        {...repeated, 'setNumber': 1}
      ],
    });
    expect(duplicate.sets, isEmpty);
    expect(duplicate.completedSets, isNull);
  });

  test('partial and malformed lists never get topped up from targetSets', () {
    final partial = WorkoutResultEvidence.fromResult({
      'totalReps': 10,
      'targetSets': 4,
      'setResults': [
        {'reps': 2, 'weightKg': 5, 'badCount': 1}
      ],
    });
    expect(partial.sets.single.reps, 2);
    expect(partial.completeBreakdown, isFalse);
    expect(partial.completedSets, isNull);
    expect(partial.volumeKg, isNull);
    for (final invalid in [
      null,
      4,
      {'reps': 2.5},
      {'reps': -1}
    ]) {
      final evidence = WorkoutResultEvidence.fromResult({
        'totalReps': 10,
        'targetSets': 4,
        'setResults': [invalid],
      });
      expect(evidence.sets, isEmpty);
    }
  });

  test('native evidence owns facts and media attaches by set identity', () {
    final summary = WorkoutEvidence.nativeSummary(
      completedReps: 4,
      recordedWarningEvents: 4,
      sets: [
        {'reps': 2, 'weightKg': 0, 'badCount': 1},
        {'reps': 2, 'weightKg': 0, 'badCount': 3},
      ],
    );
    final evidence = WorkoutResultEvidence.fromResult({
      'totalReps': 4,
      'weightKg': 999,
      'targetSets': 10,
      'feedbackCounts': {'scope_set_repeated_key': 99},
      'poseMetricsSummary': summary,
      'setResults': [
        {
          'setNumber': 2,
          'reps': 2,
          'weightKg': 0,
          'badCount': 99,
          'videoUrl': 'https://example.test/set2.mp4'
        },
        {
          'setNumber': 1,
          'reps': 2,
          'weightKg': 0,
          'badCount': 99,
          'videoLocalPath': '/real/set1.mp4'
        },
      ],
    });
    expect(evidence.completedSets, 2);
    expect(evidence.volumeKg, 0);
    expect(evidence.recordedWeightKg, 0);
    expect(evidence.sets.map((set) => set.warningEvents), [1, 3]);
    expect(evidence.sets.first.localVideoPath, '/real/set1.mp4');
    expect(evidence.sets.last.remoteVideoUrl, 'https://example.test/set2.mp4');
  });

  test(
      'native setIndex is identity and conflicting aliases do not attach media',
      () {
    final summary = WorkoutEvidence.nativeSummary(
      completedReps: 4,
      recordedWarningEvents: 0,
      sets: [
        {'reps': 2, 'weightKg': 0, 'badCount': 0},
        {'reps': 2, 'weightKg': 0, 'badCount': 0},
      ],
    );
    WorkoutResultEvidence read(List<Map<String, dynamic>> media) =>
        WorkoutResultEvidence.fromResult({
          'totalReps': 4,
          'poseMetricsSummary': summary,
          'setResults': media
        });
    final reordered = read([
      {'setIndex': 2, 'reps': 2, 'weightKg': 0, 'videoLocalPath': '/set2.mp4'},
      {'setIndex': 1, 'reps': 2, 'weightKg': 0, 'videoLocalPath': '/set1.mp4'},
    ]);
    expect(reordered.sets.map((set) => set.localVideoPath),
        ['/set1.mp4', '/set2.mp4']);
    final conflict = read([
      {
        'setNumber': 1,
        'setIndex': 2,
        'reps': 2,
        'weightKg': 0,
        'videoLocalPath': '/ambiguous.mp4'
      },
    ]);
    expect(conflict.sets.every((set) => set.localVideoPath == null), isTrue);
    final unknownWeight = WorkoutMetadataRequestDto.fromJson({
      'totalReps': 4,
      'poseMetricsSummary': summary,
      'setsDetail': [
        {'setNumber': 1, 'reps': 2, 'videoLocalPath': '/unbound-weight.mp4'}
      ],
    });
    expect(unknownWeight.effectiveSetsDetail.first.videoLocalPath, isNull);
  });

  test('DTO queue model and shared route fields retain mixed sets and media',
      () async {
    final dto = WorkoutMetadataRequestDto.fromJson({
      'clientRecordId': 'preserve-real-sets',
      'totalReps': 7,
      'targetSets': 4,
      'correctReps': 7,
      'postureScore': 95,
      'setsDetail': [
        {
          'setNumber': 1,
          'reps': 3,
          'weightKg': 0,
          'badCount': 4,
          'videoLocalPath': '/recorded/set1.mp4'
        },
        {
          'setNumber': 2,
          'reps': 4,
          'weightKg': 12.5,
          'badCount': 0,
          'videoUrl': 'https://example.test/set2.mp4'
        },
      ],
    });
    final queue = SyncQueueStorage(prefs, 'attribution');
    await queue.clear();
    await queue.enqueue(dto);
    final queued = queue.getQueue().single;
    final model = WorkoutRecordModel.fromJsonString(
        WorkoutRecordModel.fromDto(queued).toJsonString());
    final evidence = WorkoutResultEvidence.fromResult(reopen(model));
    expect(model.completedSets, 2);
    expect(model.repsPerSet, isNull);
    expect(model.accuracy, isNull);
    expect(model.assessedPostureScore, isNull);
    expect(evidence.sets.map((set) => set.reps), [3, 4]);
    expect(evidence.sets.map((set) => set.weightKg), [0, 12.5]);
    expect(evidence.sets.map((set) => set.warningEvents), [4, 0]);
    expect(evidence.volumeKg, 50);
    expect(evidence.sets.first.localVideoPath, '/recorded/set1.mp4');
    expect(evidence.sets.last.remoteVideoUrl, 'https://example.test/set2.mp4');
    expect(model.toDto().toStorageJson()['setsDetail'],
        queued.toStorageJson()['setsDetail']);
    expect(jsonEncode(model.toDto().toJson()), isNot(contains('/recorded/')));
    expect(jsonEncode(model.toDto().toJson()), isNot(contains('set2.mp4')));
  });

  test(
      'absent weight stays unknown through queue/cache while explicit zero stays known',
      () async {
    for (final weight in [null, 0]) {
      final dto = WorkoutMetadataRequestDto.fromJson({
        'clientRecordId': 'weight-$weight',
        'totalReps': 2,
        if (weight != null) 'weightKg': weight,
        'setsDetail': [
          {'setNumber': 1, 'reps': 2, if (weight != null) 'weightKg': weight},
        ],
      });
      final queued =
          WorkoutMetadataRequestDto.fromJsonString(dto.toJsonString());
      final model = WorkoutRecordModel.fromJsonString(
          WorkoutRecordModel.fromDto(queued).toJsonString());
      final evidence = WorkoutResultEvidence.fromResult(reopen(model));
      expect(evidence.sets.single.weightKg, weight);
      expect(evidence.recordedWeightKg, weight);
      expect(evidence.volumeKg, weight == null ? null : 0);
    }
  });

  test('malformed legacy sets stay invalid through DTO model and reopening',
      () {
    for (final raw in [
      'invalid-list',
      [null],
      [4],
      [
        {'setNumber': 1, 'reps': 1.5, 'weightKg': 0}
      ],
      [
        {'setNumber': 1, 'weightKg': 0}
      ],
      [
        {'setNumber': 1, 'reps': 4},
        {'setNumber': 1, 'reps': 5}
      ],
      [
        {'setNumber': 1, 'setIndex': 2, 'reps': 9}
      ],
      [
        {'setNumber': 1, 'reps': 9, 'weightKg': 'unknown'}
      ],
    ]) {
      final dto = WorkoutMetadataRequestDto.fromJson(
          {'totalReps': 9, 'setsDetail': raw});
      final queued =
          WorkoutMetadataRequestDto.fromJsonString(dto.toJsonString());
      final model = WorkoutRecordModel.fromJsonString(
          WorkoutRecordModel.fromDto(queued).toJsonString());
      final evidence = WorkoutResultEvidence.fromResult(reopen(model));
      expect(model.totalReps, 9);
      expect(model.setsDetailValid, isFalse);
      expect(evidence.sets, isEmpty);
      expect(evidence.completedSets, isNull);
      expect(evidence.volumeKg, isNull);
    }
  });

  test('unversioned remote zero is not proof of an entered bodyweight value',
      () {
    final dto = WorkoutMetadataRequestDto.fromJson({
      'totalReps': 2,
      'weightKg': 0,
      'setsDetail': [
        {'setNumber': 1, 'reps': 2, 'weightKg': 0}
      ],
    }, unversionedRemote: true);
    final evidence = WorkoutResultEvidence.fromResult(
        reopen(WorkoutRecordModel.fromDto(dto)));
    expect(evidence.completedSets, 1);
    expect(evidence.sets.single.reps, 2);
    expect(evidence.sets.single.weightKg, isNull);
    expect(evidence.volumeKg, isNull);
    final oldCache = WorkoutRecordModel.fromJson({
      'totalReps': 2,
      'weightKg': 0,
      'setsDetail': [
        {'setNumber': 1, 'reps': 2, 'weightKg': 0}
      ],
    });
    expect(WorkoutResultEvidence.fromResult(reopen(oldCache)).volumeKg, isNull);
  });

  testWidgets(
      'legacy history and shared surface show unknown breakdown, not allocated sets',
      (tester) async {
    await show(tester, {
      'totalReps': 11,
      'targetReps': 11,
      'targetSets': 3,
      'correctReps': 11,
      'incorrectReps': 0,
      'postureScore': 100,
    });
    expect(find.text('11'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    final screenshot = find.byType(Screenshot);
    expect(
        find.descendant(
            of: screenshot,
            matching: find.textContaining('Set breakdown unavailable')),
        findsOneWidget);
    expect(
        find.descendant(
            of: screenshot,
            matching: find.textContaining('Warning evidence is unavailable')),
        findsOneWidget);
    expect(find.textContaining('No warnings were recorded'), findsNothing);
    expect(find.textContaining('4 reps ·'), findsNothing);
    expect(find.textContaining('3 reps ·'), findsNothing);
    expect(find.textContaining('No workout recording is available'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'known zero-weight events remain events, and absent video is never a demo',
      (tester) async {
    final record =
        WorkoutRecordModel.fromDto(WorkoutMetadataRequestDto.fromJson({
      'totalReps': 2,
      'targetSets': 9,
      'setsDetail': [
        {'setNumber': 1, 'reps': 2, 'weightKg': 0, 'badCount': 4}
      ],
    }));
    await show(tester, reopen(record));
    expect(find.text('2 reps · 0.0kg'), findsOneWidget);
    expect(find.text('Warnings x4'), findsOneWidget);
    expect(find.textContaining('Overall form unassessed'), findsOneWidget);
    expect(find.textContaining('No recording is available for this set'),
        findsOneWidget);
    expect(find.textContaining('Perfect'), findsNothing);
    expect(find.textContaining('5s'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
