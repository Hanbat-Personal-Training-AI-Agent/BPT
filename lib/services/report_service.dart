import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';

/// 리포트 분석 집계 (GET /reports/analysis).
class ReportAnalysisCounts {
  const ReportAnalysisCounts({
    required this.totalSessions,
    required this.sessionsByExercise,
    required this.mistakeCounts,
  });

  final int totalSessions;

  /// 운동 종목 id → 세션 수.
  final Map<String, int> sessionsByExercise;

  /// 자세 피드백 키 → 누적 횟수.
  final Map<String, int> mistakeCounts;

  factory ReportAnalysisCounts.fromJson(Map<String, dynamic> json) {
    int toInt(Object? v) => v is num ? v.toInt() : 0;
    Map<String, int> entries(
            Object? list, String keyField, String countField) =>
        {
          if (list is List)
            for (final e in list.whereType<Map>())
              if (e[keyField] is String)
                e[keyField] as String: toInt(e[countField]),
        };
    return ReportAnalysisCounts(
      totalSessions: toInt(json['totalSessions']),
      sessionsByExercise: entries(json['exercises'], 'exerciseId', 'sessions'),
      mistakeCounts: entries(json['mistakes'], 'key', 'count'),
    );
  }
}

class ReportService {
  ReportService(this._apiClient);

  final ApiClient _apiClient;

  /// 기간을 안 주면 전체 기록을 집계한다.
  Future<ReportAnalysisCounts> fetchAnalysis() async {
    final response = await _apiClient.get('/reports/analysis');
    return ReportAnalysisCounts.fromJson(response.data as Map<String, dynamic>);
  }
}

final reportServiceProvider = Provider<ReportService>(
  (ref) => ReportService(ref.watch(apiClientProvider)),
);
