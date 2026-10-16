import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../features/auth/providers/auth_provider.dart';
import 'workout_records_service.dart';

/// 월별 운동 캘린더 요약 (GET /workouts/calendar).
class MonthlyCalendar {
  const MonthlyCalendar(
      {required this.workoutDates, required this.recordCount});

  /// 운동한 날짜들 (시간 없이 날짜만).
  final Set<DateTime> workoutDates;

  /// 그 달의 운동 기록 수 (하루에 여러 번 하면 모두 센다).
  final int recordCount;

  factory MonthlyCalendar.fromJson(Map<String, dynamic> json) {
    final dates = <DateTime>{};
    for (final d in (json['workoutDates'] as List? ?? const [])) {
      final parsed = DateTime.tryParse(d.toString());
      if (parsed != null) {
        dates.add(DateTime(parsed.year, parsed.month, parsed.day));
      }
    }
    var count = 0;
    for (final day in (json['dailySummaries'] as List? ?? const [])) {
      if (day is Map && day['records'] is List) {
        count += (day['records'] as List).length;
      }
    }
    return MonthlyCalendar(workoutDates: dates, recordCount: count);
  }
}

class CalendarService {
  CalendarService(this._apiClient);

  final ApiClient _apiClient;

  Future<MonthlyCalendar> fetchMonth(int year, int month) async {
    final response = await _apiClient.get(
      '/workouts/calendar',
      queryParameters: {'year': year, 'month': month},
    );
    return MonthlyCalendar.fromJson(response.data as Map<String, dynamic>);
  }
}

final calendarServiceProvider = Provider<CalendarService>(
  (ref) => CalendarService(ref.watch(apiClientProvider)),
);

/// 서버의 월별 캘린더. 키는 그 달 1일. 운동 기록이 바뀌면 다시 받는다.
/// 로그인 전이거나 연결이 안 되면 null 이라 화면은 기기 기록으로 그린다.
final monthlyCalendarProvider =
    FutureProvider.family<MonthlyCalendar?, DateTime>((ref, month) async {
  ref.watch(workoutRecordsProvider);
  if (ref.watch(authNotifierProvider).currentUser == null) return null;
  try {
    return await ref
        .watch(calendarServiceProvider)
        .fetchMonth(month.year, month.month);
  } catch (_) {
    return null;
  }
});
