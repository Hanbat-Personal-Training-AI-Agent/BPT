import 'package:bpt/data/dto/workout_metadata_dto.dart';
import 'package:bpt/data/repositories/workout_repository.dart';
import 'package:bpt/features/report/providers/report_provider.dart';
import 'package:bpt/features/report/screens/report_screen.dart';
import 'package:bpt/features/report/widgets/report_volume_tab.dart';
import 'package:bpt/models/workout_record_model.dart';
import 'package:bpt/services/workout_records_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

WorkoutRecordModel _record(DateTime date,
        {int seconds = 600, int reps = 100}) =>
    WorkoutRecordModel(
      id: date.toIso8601String(),
      exerciseId: 'squat',
      exerciseName: 'Squat',
      date: date,
      totalReps: reps,
      correctReps: reps,
      incorrectReps: 0,
      durationSeconds: seconds,
      postureScore: 90,
      feedbackNotes: const [],
    );

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
  // 2026-09-21은 월요일이라 "이번 주"의 시작일이다.
  final now = DateTime(2026, 9, 21, 12);

  test('weekly buckets: last completed week vs the week before', () {
    final data = buildReportVolume(
      [
        _record(DateTime(2026, 9, 21, 9), seconds: 600, reps: 100), // 이번 주
        _record(DateTime(2026, 9, 14, 9), seconds: 1200, reps: 200), // 지난주
        _record(DateTime(2026, 9, 8, 9), seconds: 600, reps: 50), // 지지난주
        _record(DateTime(2026, 5, 1), seconds: 9999), // 범위 밖
      ],
      ReportPeriod.weekly,
      isKo: true,
      now: now,
    );

    expect(data.labels, ['1주', '2주', '3주', '4주', '5주', '6주', '이번']);
    expect(data.minutes[reportCurrentIndex], 10);
    expect(data.minutes[reportLastCompletedIndex], 20);
    expect(data.minutes[reportLastCompletedIndex - 1], 10);
    expect(data.timeChangePct, 100);
    expect(data.totalSeconds, 2400);
    expect(data.totalReps, 350);
    expect(data.activeDays, 3);
    expect(data.avgRepsPerActiveDay, 117);
    expect(data.hasData, isTrue);
  });

  test('daily buckets end on today and split at midnight', () {
    final data = buildReportVolume(
      [
        _record(DateTime(2026, 9, 21, 0, 0), seconds: 60),
        _record(DateTime(2026, 9, 20, 23, 59), seconds: 120),
      ],
      ReportPeriod.daily,
      isKo: true,
      now: now,
    );
    expect(data.labels.last, '오늘');
    expect(data.labels.first, '화'); // 9/15
    expect(data.minutes[reportCurrentIndex], 1);
    expect(data.minutes[reportLastCompletedIndex], 2);
  });

  test('monthly buckets cross the year boundary', () {
    final data = buildReportVolume(
      [
        _record(DateTime(2025, 12, 31, 23), seconds: 60),
        _record(DateTime(2025, 6, 30), seconds: 60), // 범위 밖 (6개월 초과)
      ],
      ReportPeriod.monthly,
      isKo: true,
      now: DateTime(2026, 1, 15),
    );
    expect(data.labels, ['7월', '8월', '9월', '10월', '11월', '12월', '이번']);
    expect(data.minutes[reportLastCompletedIndex], 1);
    expect(data.totalSeconds, 60);
  });

  test('no records gives zeros and no change badge', () {
    final data =
        buildReportVolume(const [], ReportPeriod.weekly, isKo: false, now: now);
    expect(data.hasData, isFalse);
    expect(data.timeChangePct, isNull);
    expect(data.avgRepsPerActiveDay, 0);
    expect(data.labels.first, 'W1');
    expect(data.labels.last, 'Now');
  });

  testWidgets('volume tab renders stats, switches period and section',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final records = [
      _record(today.subtract(const Duration(days: 7)),
          seconds: 1500, reps: 200),
      _record(today.subtract(const Duration(days: 14)),
          seconds: 900, reps: 100),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        workoutRecordsProvider.overrideWith(
            (ref) => WorkoutRecordsNotifier(_FakeRepository(records))),
      ],
      child: const MaterialApp(home: ReportScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('리포트'), findsOneWidget);
    expect(find.text('운동량'), findsOneWidget);
    expect(find.text('총 시간'), findsOneWidget);
    expect(find.text('40m'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    expect(find.text('2일'), findsOneWidget);
    expect(find.text('+67%'), findsOneWidget);
    expect(find.text('이번'), findsNWidgets(2)); // 두 차트의 x축에 하나씩

    // y축: 가장 긴 구간(25분) 기준으로 0 / 10m / 20m / 30m 눈금이 왼쪽에 깔린다.
    for (final label in ['10m', '20m', '30m']) {
      expect(find.text(label), findsOneWidget);
    }
    // 반복 횟수 차트도 같은 방식: 가장 큰 구간(200회) 기준 0 / 100 / 200.
    // '0'은 두 차트의 y축에 하나씩 있다.
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('100'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);

    // 막대를 누르면 그 구간의 운동 시간이 막대 위에 글자로 뜨고, 다시 누르면 사라진다.
    expect(find.text('25m'), findsNothing);
    await tester.tap(find.byKey(const Key('time-bar-5')));
    await tester.pumpAndSettle();
    expect(find.text('25m'), findsOneWidget);
    await tester.tap(find.byKey(const Key('time-bar-4')));
    await tester.pumpAndSettle();
    expect(find.text('25m'), findsNothing);
    expect(find.text('15m'), findsOneWidget);
    await tester.tap(find.byKey(const Key('time-bar-4')));
    await tester.pumpAndSettle();
    expect(find.text('15m'), findsNothing);

    // 반복 횟수 차트도 막대를 누르면 그 구간의 횟수가 뜬다.
    await tester.tap(find.byKey(const Key('reps-bar-5')));
    await tester.pumpAndSettle();
    expect(find.text('200회'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reps-bar-5')));
    await tester.pumpAndSettle();
    expect(find.text('200회'), findsNothing);

    // 양 끝 막대(첫 구간, 현재 구간)도 값 글자가 막대 가운데에 정렬된다.
    for (final (prefix, text) in [('time-bar', '0m'), ('reps-bar', '0회')]) {
      for (final i in [0, 6]) {
        await tester.tap(find.byKey(Key('$prefix-$i')));
        await tester.pumpAndSettle();
        final valueText = find.text(text);
        expect(valueText, findsOneWidget);
        expect(
          tester.getCenter(valueText).dx,
          closeTo(tester.getCenter(find.byKey(Key('$prefix-$i'))).dx, 0.5),
          reason: '$prefix $i',
        );
        await tester.tap(find.byKey(Key('$prefix-$i'))); // 닫기
        await tester.pumpAndSettle();
      }
    }

    await tester.tap(find.byKey(const Key('time-bar-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('일별'));
    await tester.pumpAndSettle();
    expect(find.text('오늘'), findsNWidgets(2));
    expect(find.text('25m'), findsNothing); // 단위를 바꾸면 선택 해제

    await tester.tap(find.text('분석'));
    await tester.pumpAndSettle();
    expect(find.text('분석 화면은 곧 만나볼 수 있어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('niceTimeAxis picks a clean range for the longest bar', () {
    void expectAxis(double maxMin, double axisMax, double step) {
      final axis = niceTimeAxis(maxMin);
      expect(axis.max, axisMax, reason: 'max for $maxMin');
      expect(axis.step, step, reason: 'step for $maxMin');
    }

    expectAxis(0, 60, 30); // 기록 없음
    expectAxis(3, 5, 5);
    expectAxis(25, 30, 10);
    expectAxis(30, 30, 10);
    expectAxis(31, 45, 15); // 10분 간격이면 4칸이라 15분 간격으로
    expectAxis(55, 60, 20);
    expectAxis(100, 120, 60);
    expectAxis(200, 240, 120);
    expectAxis(2400, 2520, 840); // 40시간: 1시간 단위(14시간 간격)로 3칸 이내
    expect(niceTimeAxis(25).ticks, [0, 10, 20, 30]);
  });

  test('niceCountAxis picks a clean range for the highest rep count', () {
    void expectAxis(double maxCount, double axisMax, double step) {
      final axis = niceCountAxis(maxCount);
      expect(axis.max, axisMax, reason: 'max for $maxCount');
      expect(axis.step, step, reason: 'step for $maxCount');
    }

    expectAxis(0, 100, 50); // 기록 없음
    expectAxis(3, 3, 1);
    expectAxis(7, 10, 5); // 2 간격이면 4칸이라 5 간격으로
    expectAxis(143, 150, 50);
    expectAxis(200, 200, 100);
    expectAxis(1284, 1500, 500);
    expectAxis(4200, 6000, 2000); // 1000 간격이면 5칸이라 2000 간격으로
    expect(niceCountAxis(143).ticks, [0, 50, 100, 150]);
  });
}
