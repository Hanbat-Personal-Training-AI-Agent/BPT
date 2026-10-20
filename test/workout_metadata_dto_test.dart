import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dto = WorkoutMetadataRequestDto(
    clientRecordId: 'c-1',
    exerciseId: 'squat',
    exerciseName: 'Squat',
    date: DateTime(2026, 10, 9),
    weightKg: 60,
    totalReps: 22,
    correctReps: 20,
    incorrectReps: 2,
    durationSeconds: 300,
    postureScore: 0,
    feedbackNotes: [],
    targetSets: 3,
    setsDetail: [
      const WorkoutSetDetail(setNumber: 1, reps: 12, weightKg: 60),
      const WorkoutSetDetail(setNumber: 2, reps: 10, weightKg: 50),
    ],
    feedbackCounts: {'squat_knee_valgus': 2},
  );

  test('sends sets detail, totals and feedback counts to the server', () {
    final json = dto.toJson();
    expect(json['totalSets'], 2);
    expect(json['totalVolume'], 60 * 12 + 50 * 10);
    expect(json['setsDetail'], [
      {'setNumber': 1, 'reps': 12, 'weightKg': 60.0},
      {'setNumber': 2, 'reps': 10, 'weightKg': 50.0},
    ]);
    expect(json['feedbackCounts'], {'squat_knee_valgus': 2});
  });

  test('offline queue round trip keeps the new fields', () {
    final back = WorkoutMetadataRequestDto.fromJsonString(dto.toJsonString());
    expect(back.setsDetail.map((s) => s.reps), [12, 10]);
    expect(back.feedbackCounts, {'squat_knee_valgus': 2});
    expect(back.totalVolume, dto.totalVolume);
  });
}
