import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/data/repositories/workout_repository.dart';
import 'package:bpt/features/report/providers/report_analysis_provider.dart';
import 'package:bpt/features/report/screens/report_screen.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:bpt/services/workout_records_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

WorkoutRecordModel _record(String exerciseId,
        {double weightKg = 0, Map<String, int> feedbackCounts = const {}}) =>
    WorkoutRecordModel(
      id: '$exerciseId-${_seq++}',
      exerciseId: exerciseId,
      exerciseName: exerciseId,
      date: DateTime(2026, 10, 1),
      weightKg: weightKg,
      totalReps: 10,
      correctReps: 10,
      incorrectReps: 0,
      durationSeconds: 60,
      postureScore: 0,
      feedbackNotes: const [],
      feedbackCounts: feedbackCounts,
    );
var _seq = 0;

class _FakeRepository implements IWorkoutRepository {
  _FakeRepository(this.records);
  final List<WorkoutRecordModel> records;

  @override
  Future<List<WorkoutRecordModel>> getWorkoutRecords() async => records;

  @override
  Future<WorkoutRecordModel> submitWorkoutRecord(
          WorkoutMetadataRequestDto metadataDto) =>
      throw UnimplementedError();
}

void main() {
  test('ratios come from real records and add up to exactly 100%', () {
    final data = buildReportAnalysis([
      _record('squat'),
      _record('squat'),
      _record('squat'),
      _record('benchpress'),
      _record('benchpress'),
      _record('deadlift'),
    ]);
    expect(data.totalSessions, 6);
    expect(data.ratios.map((r) => r.labelKo), ['스쿼트', '벤치프레스', '데드리프트']);
    expect(data.ratios.map((r) => r.percent), [50, 33, 17]);
    expect(data.ratios.fold<int>(0, (a, r) => a + r.percent), 100);
    expect(data.insight(true), contains('스쿼트를 가장 많이 했어'));
  });

  test('mistakes add up feedback counts across records, most frequent first', () {
    final data = buildReportAnalysis([
      _record('squat', feedbackCounts: {'squat_knee_valgus': 2, 'squat_shallow': 1}),
      _record('squat', feedbackCounts: {'squat_knee_valgus': 3}),
      _record('pushup', feedbackCounts: {'pushup_hip_sag': 2, 'unknown_key': 9}),
    ]);
    expect(data.mistakes.map((m) => m.labelKo),
        ['무릎 안쪽 모임 · 스쿼트', '엉덩이 처짐 · 푸쉬업', '앉는 깊이 부족 · 스쿼트']);
    expect(data.mistakes.map((m) => m.count), [5, 2, 1]);
    expect(data.totalMistakes, 8);
    expect(data.insight(true), contains('무릎 안쪽 모임이 가장 자주 보였어'));
  });

  test('no records → empty ratios, no mistakes, waiting message', () {
    final data = buildReportAnalysis(const []);
    expect(data.totalSessions, 0);
    expect(data.ratios, isEmpty);
    expect(data.mistakes, isEmpty);
    expect(data.insight(true), contains('기록이 쌓이면'));
  });

  testWidgets('analysis tab renders real ratios and the empty mistakes state',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        workoutRecordsProvider.overrideWith((ref) => WorkoutRecordsNotifier(
            _FakeRepository([_record('squat'), _record('pushup')]))),
      ],
      child: const MaterialApp(home: ReportScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('분석'));
    await tester.pumpAndSettle();

    expect(find.text('종목별 비율'), findsOneWidget);
    expect(find.text('세션'), findsOneWidget);
    expect(find.text('스쿼트'), findsWidgets);
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.text('자주 나온 실수'), findsOneWidget);
    expect(find.text('자세 실수 분석은 곧 보여줄게!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
