import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';

/// 홈 화면 요약 (GET /users/me/dashboard).
class DashboardSummary {
  const DashboardSummary({
    required this.date,
    required this.todayWorkoutMinutes,
    required this.todayCompletedSets,
    required this.todayTotalReps,
    required this.weeklyCompletedCount,
    required this.daysSinceLastScan,
  });

  /// 서버가 계산한 기준 날짜. 기기 날짜와 다르면 "오늘"·"이번 주" 값이 어긋난다.
  final DateTime? date;
  final int todayWorkoutMinutes;
  final int todayCompletedSets;
  final int todayTotalReps;

  /// 이번 주에 운동한 날 수.
  final int weeklyCompletedCount;

  /// 마지막 체형 측정 후 지난 날 수. 한 번도 측정 안 했으면 null.
  final int? daysSinceLastScan;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    int toInt(Object? v) => v is num ? v.toInt() : 0;
    final days = json['daysSinceLastScan'];
    return DashboardSummary(
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      todayWorkoutMinutes: toInt(json['todayWorkoutMinutes']),
      todayCompletedSets: toInt(json['todayCompletedSets']),
      todayTotalReps: toInt(json['todayTotalReps']),
      weeklyCompletedCount: toInt(json['weeklyCompletedCount']),
      daysSinceLastScan: days is num ? days.toInt() : null,
    );
  }

  /// 서버 기준 날짜가 기기의 오늘과 같은지.
  bool isFor(DateTime now) =>
      date != null &&
      date!.year == now.year &&
      date!.month == now.month &&
      date!.day == now.day;
}

class DashboardService {
  DashboardService(this._apiClient);

  final ApiClient _apiClient;

  Future<DashboardSummary> fetchSummary() async {
    final response = await _apiClient.get('/users/me/dashboard');
    return DashboardSummary.fromJson(response.data as Map<String, dynamic>);
  }
}

final dashboardServiceProvider = Provider<DashboardService>(
  (ref) => DashboardService(ref.watch(apiClientProvider)),
);
