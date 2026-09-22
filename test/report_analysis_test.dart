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

class _EmptyRepository implements IWorkoutRepository {
  @override
  Future<List<WorkoutRecordModel>> getWorkoutRecords() async => const [];

  @override
  Future<WorkoutRecordModel> submitWorkoutRecord(
          WorkoutMetadataRequestDto metadataDto) =>
      throw UnimplementedError();
}

void main() {
  test('mock exercise ratios add up to exactly 100%', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final data = container.read(reportAnalysisProvider);
    final sum = data.ratios.fold<int>(0, (a, r) => a + r.percent);
    expect(sum, 100);
    expect(data.ratios.length, 6);
    expect(data.ratios.any((r) => r.labelKo == '기타'), isFalse);
  });

  test('mistake counts add up to the displayed total', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final data = container.read(reportAnalysisProvider);
    final sum = data.mistakes.fold<int>(0, (a, m) => a + m.count);
    expect(sum, data.totalMistakes);
  });

  testWidgets('analysis tab renders the ratio donut, mistakes and insight',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        workoutRecordsProvider.overrideWith(
            (ref) => WorkoutRecordsNotifier(_EmptyRepository())),
      ],
      child: const MaterialApp(home: ReportScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('분석'));
    await tester.pumpAndSettle();

    expect(find.text('종목별 비율'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('세션'), findsOneWidget);
    expect(find.text('스쿼트'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('랫풀다운'), findsOneWidget);
    expect(find.text('8%'), findsOneWidget);
    expect(find.text('기타'), findsNothing);

    expect(find.text('자주 나온 실수'), findsOneWidget);
    expect(find.text('총 68회'), findsOneWidget);
    expect(find.text('무릎 안쪽 모임'), findsOneWidget);
    expect(find.text('24회'), findsOneWidget);

    expect(find.textContaining('하체 운동을 많이 했고'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
