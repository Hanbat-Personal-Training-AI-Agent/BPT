import 'package:bpt/features/workout/data/workout_evidence.dart';
import 'package:bpt/features/workout/widgets/workout_record_completion_text.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkoutRecordModel record(List<int>? reps) => WorkoutRecordModel.fromJson({
      'totalReps': reps?.fold<int>(0, (a, b) => a + b) ?? 12,
      'targetSets': 3,
      'poseMetricsSummary': reps == null
          ? {}
          : WorkoutEvidence.nativeSummary(
              completedReps: reps.fold<int>(0, (a, b) => a + b),
              recordedWarningEvents: 0,
              sets: reps
                  .map((n) => <String, dynamic>{
                        'reps': n,
                        'weightKg': 0,
                        'badCount': 0
                      })
                  .toList()),
    });

void main() {
  test('actual, mixed and legacy unknown sets never derive from targetSets',
      () {
    expect(record([12]).completedSets, 1);
    expect(record([12]).repsPerSet, 12);
    expect(record([1, 5]).completedSets, 2);
    expect(record([1, 5]).repsPerSet, isNull);
    expect(record(null).completedSets, isNull);
    expect(record(null).repsPerSet, isNull);
    expect(record([]).completedSets, 0);
  });
  testWidgets(
      'home and calendar shared presenter distinguishes actual sets from a goal',
      (tester) async {
    for (final sample in [
      ([12], '1세트 · 총 12회'),
      ([1, 5], '2세트 · 총 6회'),
      (null, '총 12회 · 목표 3세트')
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: WorkoutRecordCompletionText(
                  record: record(sample.$1), isKo: true))));
      expect(find.text(sample.$2), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
