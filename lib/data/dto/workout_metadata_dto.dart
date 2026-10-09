import 'dart:convert';

/// On-Device AI Edge Computing Metadata Request DTO
/// Transmits strictly lightweight metadata (Reps, postureScore, duration, posture feedback notes)
/// NEVER transmits raw video files or camera frames to Spring Boot backend.
class WorkoutMetadataRequestDto {
  final String clientRecordId;
  final String exerciseId;
  final String exerciseName;
  final DateTime date;
  final double weightKg;
  final int totalReps;
  final int correctReps;
  final int incorrectReps;
  final int durationSeconds;
  final double postureScore; // 핵심 피드백 점수 (0.0 ~ 100.0)
  final List<String> feedbackNotes;
  final int targetReps;
  final int targetSets;
  final Map<String, dynamic>? poseMetricsSummary; // On-device joint angles/metrics metadata summary

  /// 세트별 기록. 서버 setsDetail: {setNumber, reps, weightKg}
  final List<WorkoutSetDetail> setsDetail;

  /// 자세 피드백 키별 횟수 (kori_feedback_lines.dart 키). 실제 판정에서 나온 것만 담는다.
  final Map<String, int> feedbackCounts;

  /// 실제로 수행한 세트 수. setsDetail 이 있으면 그 개수.
  int get totalSets => setsDetail.isNotEmpty ? setsDetail.length : targetSets;

  /// 총 볼륨(kg × 회). setsDetail 이 없으면 대표 무게 × 총 반복.
  int get totalVolume => setsDetail.isNotEmpty
      ? setsDetail.fold(0, (sum, s) => sum + (s.weightKg * s.reps).round())
      : (weightKg * totalReps).round();

  const WorkoutMetadataRequestDto({
    required this.clientRecordId,
    required this.exerciseId,
    required this.exerciseName,
    required this.date,
    this.weightKg = 0.0,
    required this.totalReps,
    required this.correctReps,
    required this.incorrectReps,
    required this.durationSeconds,
    required this.postureScore,
    required this.feedbackNotes,
    this.targetReps = 0,
    this.targetSets = 1,
    this.poseMetricsSummary,
    this.setsDetail = const [],
    this.feedbackCounts = const {},
  });

  Map<String, dynamic> toJson() => {
        'clientRecordId': clientRecordId,
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'date': date.toIso8601String(),
        'weightKg': weightKg,
        'totalReps': totalReps,
        'correctReps': correctReps,
        'incorrectReps': incorrectReps,
        'durationSeconds': durationSeconds,
        'postureScore': postureScore,
        'feedbackNotes': feedbackNotes,
        'targetReps': targetReps,
        'targetSets': targetSets,
        'poseMetricsSummary': poseMetricsSummary ?? {},
        'totalSets': totalSets,
        'totalVolume': totalVolume,
        'setsDetail': setsDetail.map((s) => s.toJson()).toList(),
        'feedbackCounts': feedbackCounts,
      };

  factory WorkoutMetadataRequestDto.fromJson(Map<String, dynamic> json) {
    return WorkoutMetadataRequestDto(
      clientRecordId: json['clientRecordId'] as String? ?? '',
      exerciseId: json['exerciseId'] as String? ?? '',
      exerciseName: json['exerciseName'] as String? ?? '',
      date: json['date'] != null
          ? DateTime.tryParse(json['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0.0,
      totalReps: (json['totalReps'] as num?)?.toInt() ?? 0,
      correctReps: (json['correctReps'] as num?)?.toInt() ?? 0,
      incorrectReps: (json['incorrectReps'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      postureScore: (json['postureScore'] as num?)?.toDouble() ?? 0.0,
      feedbackNotes: (json['feedbackNotes'] as List?)?.cast<String>() ?? [],
      targetReps: (json['targetReps'] as num?)?.toInt() ?? 0,
      targetSets: (json['targetSets'] as num?)?.toInt() ?? 1,
      poseMetricsSummary: json['poseMetricsSummary'] as Map<String, dynamic>?,
      setsDetail: (json['setsDetail'] as List?)
              ?.whereType<Map>()
              .map((m) => WorkoutSetDetail.fromJson(m.cast<String, dynamic>()))
              .toList() ??
          const [],
      feedbackCounts: (json['feedbackCounts'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)) ??
          const {},
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory WorkoutMetadataRequestDto.fromJsonString(String source) =>
      WorkoutMetadataRequestDto.fromJson(
          jsonDecode(source) as Map<String, dynamic>);
}

/// Spring Boot Server Response DTO after registering/syncing workout metadata
class WorkoutMetadataResponseDto {
  final String serverRecordId;
  final String clientRecordId;
  final double postureScore;
  final bool success;
  final String message;
  final DateTime syncedAt;

  const WorkoutMetadataResponseDto({
    required this.serverRecordId,
    required this.clientRecordId,
    required this.postureScore,
    required this.success,
    required this.message,
    required this.syncedAt,
  });

  factory WorkoutMetadataResponseDto.fromJson(Map<String, dynamic> json) {
    return WorkoutMetadataResponseDto(
      serverRecordId: json['serverRecordId'] as String? ?? json['id'] as String? ?? '',
      clientRecordId: json['clientRecordId'] as String? ?? '',
      postureScore: (json['postureScore'] as num?)?.toDouble() ?? 0.0,
      success: json['success'] as bool? ?? true,
      message: json['message'] as String? ?? 'Record synced successfully',
      syncedAt: json['syncedAt'] != null
          ? DateTime.tryParse(json['syncedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// 세트 하나의 기록 (서버 WorkoutSetRecordDto).
class WorkoutSetDetail {
  const WorkoutSetDetail({
    required this.setNumber,
    required this.reps,
    required this.weightKg,
  });

  final int setNumber;
  final int reps;
  final double weightKg;

  Map<String, dynamic> toJson() => {
        'setNumber': setNumber,
        'reps': reps,
        'weightKg': weightKg,
      };

  factory WorkoutSetDetail.fromJson(Map<String, dynamic> json) =>
      WorkoutSetDetail(
        setNumber: (json['setNumber'] as num?)?.toInt() ?? 0,
        reps: (json['reps'] as num?)?.toInt() ?? 0,
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
      );
}
