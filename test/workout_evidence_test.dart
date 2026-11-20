import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/features/workout/data/workout_evidence.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:bpt/features/workout/providers/workout_provider.dart';
import 'package:bpt/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
      'repeated warning events never become rep accuracy, even at completed goal',
      () {
    final summary = WorkoutEvidence.nativeSummary(
        completedReps: 1,
        recordedWarningEvents: 4,
        sets: [
          {'reps': 1, 'weightKg': 0, 'badCount': 4}
        ]);
    final model = WorkoutRecordModel.fromJson({
      'id': 'x',
      'totalReps': 1,
      'targetReps': 1,
      'correctReps': 0,
      'incorrectReps': 0,
      'poseMetricsSummary': summary
    });
    expect(model.accuracy, isNull);
    expect(model.postureScore, isNull);
    expect(model.assessedPostureScore, isNull);
    expect(model.achievement, 100);
    expect(
        WorkoutEvidence.details(
            model.poseMetricsSummary)?['recordedWarningEvents'],
        4);
    expect(WorkoutEvidence.completionPercent(4, 10), 40);
    expect(WorkoutEvidence.completionPercent(10, 0), isNull);
  });

  test(
      'legacy numeric zero is retained raw but is not validation, missing score stays null',
      () {
    for (final score in [null, 0, 95]) {
      final model = WorkoutRecordModel.fromJson(
          {'totalReps': 10, 'correctReps': 10, 'postureScore': score});
      expect(model.postureScore, score);
      expect(model.accuracy, isNull);
      expect(model.assessedPostureScore, isNull);
      expect(model.toDto().toJson()['postureScore'], score);
      expect(model.copyWith(clearPostureScore: true).postureScore, isNull);
      expect(model.copyWith().postureScore, score);
    }
  });

  test(
      'unknown evidence survives DTO, local cache, sync queue and record copies',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final summary = WorkoutEvidence.nativeSummary(
        completedReps: 10,
        recordedWarningEvents: 0,
        sets: [
          {'reps': 10, 'weightKg': 5, 'badCount': 0}
        ]);
    final dto = WorkoutMetadataRequestDto(
        clientRecordId: 'unknown',
        exerciseId: 'squat',
        exerciseName: 'Squat',
        date: DateTime(2026, 10, 30),
        totalReps: 10,
        correctReps: 0,
        incorrectReps: 0,
        durationSeconds: 60,
        postureScore: null,
        feedbackNotes: [],
        poseMetricsSummary: summary);
    final queue = SyncQueueStorage(prefs, 'A');
    await queue.enqueue(dto);
    final restored = queue.getQueue().single;
    expect(restored.toJson()['postureScore'], isNull);
    final cached = WorkoutRecordModel.fromDto(restored)
        .copyWith(serverId: 'server', isSynced: true);
    final roundtrip = WorkoutRecordModel.fromJsonString(cached.toJsonString());
    expect(roundtrip.toDto().poseMetricsSummary, summary);
    expect(roundtrip.accuracy, isNull);
    expect(
        WorkoutEvidence.details(
            roundtrip.poseMetricsSummary)?['formAssessment'],
        'not_available');
  });

  testWidgets('legacy demo timers cannot produce a simulated posture score',
      (tester) async {
    final demo = WorkoutNotifier();
    demo.initialize('squat', 3, 1);
    demo.startCountdown();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    expect(demo.state.postureScore, isNull);
    expect(demo.state.feedbackMessage, isNot(contains('Perfect rep')));
    demo.dispose();
  });
}
