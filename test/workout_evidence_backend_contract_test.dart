import 'dart:convert';
import 'dart:io';
import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/features/workout/data/workout_evidence.dart';
import 'package:bpt/features/workout/screens/workout_result_screen.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('shared native fixture keeps events separate from correctness', () {
    final raw = jsonDecode(
        File('test/fixtures/workout_evidence_v1_request.json')
            .readAsStringSync()) as Map<String, dynamic>;
    final dto = WorkoutMetadataRequestDto.fromJson(raw);
    final model = WorkoutRecordModel.fromDto(dto);
    expect(
        WorkoutEvidence.details(
            model.poseMetricsSummary)?['recordedWarningEvents'],
        4);
    expect(model.totalReps, 1);
    expect(model.accuracy, isNull);
    expect(model.postureScore, isNull);
    expect(model.achievement, 10);
    expect(
        WorkoutRecordModel.fromJsonString(model.toJsonString())
            .toDto()
            .poseMetricsSummary,
        dto.poseMetricsSummary);
  });

  test('malformed deployed legacy summaries and unknown versions fail closed',
      () {
    for (final summary in [
      'not-json',
      '{}',
      [1],
      true,
      4,
      null
    ]) {
      final dto =
          WorkoutMetadataRequestDto.fromJson({'poseMetricsSummary': summary});
      expect(dto.poseMetricsSummary, isNull);
      expect(
          WorkoutRecordModel.fromJson({'poseMetricsSummary': summary})
              .poseMetricsSummary,
          isEmpty);
    }
    final raw = jsonDecode(
        File('test/fixtures/workout_evidence_v1_request.json')
            .readAsStringSync()) as Map<String, dynamic>;
    final summary = raw['poseMetricsSummary'] as Map<String, dynamic>;
    final evidence = summary['workoutEvidence'] as Map<String, dynamic>;
    for (final mutation in <String, dynamic>{
      'version': 2,
      'assessedReps': 1,
      'recordedWarningEvents': -1
    }.entries) {
      final altered = {
        ...summary,
        'workoutEvidence': {...evidence, mutation.key: mutation.value}
      };
      expect(WorkoutEvidence.details(altered), isNull);
    }
    expect(
        WorkoutEvidence.details({
          'oldAngles': [1, 2]
        }),
        isNull);
    expect(WorkoutEvidence.details(summary, completedReps: 2), isNull);
  });

  const responsePath = String.fromEnvironment('BPT_BACKEND_CONTRACT_RESPONSE');
  testWidgets(
      'actual JVM service response reaches fresh-cache history without correctness inference',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final font = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf'));
    await font.load();
    final raw = jsonDecode(File(responsePath).readAsStringSync())
        as Map<String, dynamic>;
    final record =
        WorkoutRecordModel.fromDto(WorkoutMetadataRequestDto.fromJson(raw));
    expect(record.poseMetricsSummary,
        isNotEmpty); // Server payload, no cache/record-ID fallback.
    expect(record.accuracy, isNull);
    expect(record.achievement, 10);
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
          theme: ThemeData(fontFamily: 'Pretendard'),
          home: WorkoutResultScreen(
              result: {...raw, 'date': record.date, 'isHistory': true})),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('목표 횟수 10% 완료'), findsOneWidget);
    expect(find.text('경고 4회'), findsOneWidget);
    expect(find.textContaining('전체 자세 판정: 미확인'), findsOneWidget);
    expect(find.textContaining('완벽'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: responsePath.isEmpty);
}
