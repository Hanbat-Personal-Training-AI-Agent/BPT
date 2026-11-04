import 'dart:convert';
import 'dart:math';
import '../../features/workout/data/workout_evidence.dart';

/// 새 운동 기록 번호(UUID v4). 서버는 이 번호를 모든 계정에서 하나뿐인 값으로
/// 다루므로, 시각만으로 만들면 다른 사람 기록과 겹칠 수 있다.
String newClientRecordId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// On-Device AI Edge Computing Metadata Request DTO
/// Transmits strictly lightweight metadata (Reps, postureScore, duration, posture feedback notes)
/// NEVER transmits raw video files or camera frames to Spring Boot backend.
class WorkoutMetadataRequestDto {
  final String clientRecordId;
  final String exerciseId;
  final String exerciseName;
  final DateTime date;
  final double weightKg;

  /// Local presence metadata. The legacy wire still requires a numeric fallback.
  final bool weightRecorded;
  final int totalReps;
  final int correctReps;
  final int incorrectReps;
  final int durationSeconds;
  final double?
      postureScore; // Raw legacy value only; missing is not a measured zero.
  final List<String> feedbackNotes;
  final int targetReps;
  final int targetSets;
  final Map<String, dynamic>?
      poseMetricsSummary; // On-device joint angles/metrics metadata summary

  /// 세트별 기록. 서버 setsDetail: {setNumber, reps, weightKg}
  final List<WorkoutSetDetail> setsDetail;
  final bool setsDetailValid;

  /// 자세 피드백 키별 횟수 (kori_feedback_lines.dart 키). 실제 판정에서 나온 것만 담는다.
  final Map<String, int> feedbackCounts;

  /// V1 evidence owns actual sets. Legacy setsDetail remains a compatibility input only.
  List<WorkoutSetDetail> get effectiveSetsDetail {
    final evidence =
        WorkoutEvidence.details(poseMetricsSummary, completedReps: totalReps);
    if (evidence == null) return setsDetail;
    return (evidence['sets'] as List).indexed.map((entry) {
      final set = entry.$2 as Map;
      final matching =
          (setsDetailValid ? setsDetail : const <WorkoutSetDetail>[]).where(
              (row) =>
                  row.setNumber == entry.$1 + 1 &&
                  row.reps == set['reps'] &&
                  row.weightRecorded &&
                  row.weightKg == set['weightKg']);
      final media = matching.length == 1 ? matching.single : null;
      return WorkoutSetDetail(
          setNumber: entry.$1 + 1,
          reps: set['reps'] as int,
          weightKg: (set['weightKg'] as num).toDouble(),
          warningEvents: set['badCount'] as int,
          videoLocalPath: media?.videoLocalPath,
          videoRemoteUrl: media?.videoRemoteUrl);
    }).toList();
  }

  double get effectiveWeightKg {
    if (WorkoutEvidence.details(poseMetricsSummary, completedReps: totalReps) ==
        null) {
      return weightKg;
    }
    return effectiveSetsDetail.fold<double>(
        0, (best, set) => set.weightKg > best ? set.weightKg : best);
  }

  bool get effectiveWeightRecorded =>
      WorkoutEvidence.details(poseMetricsSummary, completedReps: totalReps) !=
          null ||
      weightRecorded;

  bool get effectiveSetsDetailValid =>
      WorkoutEvidence.details(poseMetricsSummary, completedReps: totalReps) !=
          null ||
      setsDetailValid;

  int get totalSets {
    final evidence =
        WorkoutEvidence.details(poseMetricsSummary, completedReps: totalReps);
    if (evidence != null) return effectiveSetsDetail.length;
    return setsDetail.isNotEmpty ? setsDetail.length : targetSets;
  }

  /// Native v1: kg × actual reps, round the final sum once for the existing integer wire field.
  int get totalVolume {
    if (WorkoutEvidence.details(poseMetricsSummary, completedReps: totalReps) !=
        null) {
      return effectiveSetsDetail
          .fold<double>(0, (sum, s) => sum + s.weightKg * s.reps)
          .round();
    }
    // Historical legacy behavior is deliberately unchanged.
    return setsDetail.isNotEmpty
        ? setsDetail.fold(0, (sum, s) => sum + (s.weightKg * s.reps).round())
        : (weightKg * totalReps).round();
  }

  const WorkoutMetadataRequestDto({
    required this.clientRecordId,
    required this.exerciseId,
    required this.exerciseName,
    required this.date,
    double? weightKg,
    bool? weightRecorded,
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
    this.setsDetailValid = true,
    this.feedbackCounts = const {},
  })  : weightKg = weightKg ?? 0.0,
        weightRecorded = weightRecorded ?? (weightKg != null);

  Map<String, dynamic> toJson() => {
        'clientRecordId': clientRecordId,
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'date': date.toIso8601String(),
        'weightKg': effectiveWeightKg,
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
        'setsDetail': effectiveSetsDetail.map((s) => s.toJson()).toList(),
        'feedbackCounts': feedbackCounts,
      };

  /// Preserve local evidence/media without adding private paths to the API body.
  Map<String, dynamic> toStorageJson() => {
        ...toJson(),
        'weightRecorded': effectiveWeightRecorded,
        'setsDetailValid': effectiveSetsDetailValid,
        'setsDetail':
            effectiveSetsDetail.map((set) => set.toStorageJson()).toList(),
      };

  factory WorkoutMetadataRequestDto.fromJson(Map<String, dynamic> json,
      {bool unversionedRemote = false}) {
    return WorkoutMetadataRequestDto(
      clientRecordId: json['clientRecordId'] as String? ?? '',
      exerciseId: json['exerciseId'] as String? ?? '',
      exerciseName: json['exerciseName'] as String? ?? '',
      date: json['date'] != null
          ? DateTime.tryParse(json['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      weightRecorded: json['weightRecorded'] as bool? ??
          (unversionedRemote && json['weightKg'] == 0 ? false : null),
      totalReps: (json['totalReps'] as num?)?.toInt() ?? 0,
      correctReps: (json['correctReps'] as num?)?.toInt() ?? 0,
      incorrectReps: (json['incorrectReps'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      postureScore: (json['postureScore'] as num?)?.toDouble(),
      feedbackNotes: (json['feedbackNotes'] as List?)?.cast<String>() ?? [],
      targetReps: (json['targetReps'] as num?)?.toInt() ?? 0,
      targetSets: (json['targetSets'] as num?)?.toInt() ?? 1,
      poseMetricsSummary:
          WorkoutEvidence.summaryObject(json['poseMetricsSummary']),
      setsDetail: json['setsDetail'] is List
          ? (json['setsDetail'] as List)
              .whereType<Map>()
              .map((m) => WorkoutSetDetail.fromJson(m.cast<String, dynamic>(),
                  unversionedRemote: unversionedRemote))
              .toList()
          : const [],
      setsDetailValid: json['setsDetailValid'] != false &&
          WorkoutSetDetail.validJsonList(json['setsDetail']),
      feedbackCounts: (json['feedbackCounts'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)) ??
          const {},
    );
  }

  /// 기록 번호만 바꾼 사본.
  WorkoutMetadataRequestDto withClientRecordId(String id) =>
      WorkoutMetadataRequestDto.fromJson(
          {...toStorageJson(), 'clientRecordId': id});

  String toJsonString() => jsonEncode(toStorageJson());

  factory WorkoutMetadataRequestDto.fromJsonString(String source) =>
      WorkoutMetadataRequestDto.fromJson(
          jsonDecode(source) as Map<String, dynamic>);
}

/// Spring Boot Server Response DTO after registering/syncing workout metadata
class WorkoutMetadataResponseDto {
  final String serverRecordId;
  final String clientRecordId;
  final double? postureScore;
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
      serverRecordId:
          json['serverRecordId'] as String? ?? json['id'] as String? ?? '',
      clientRecordId: json['clientRecordId'] as String? ?? '',
      postureScore: (json['postureScore'] as num?)?.toDouble(),
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
    double? weightKg,
    bool? weightRecorded,
    this.warningEvents,
    this.videoLocalPath,
    this.videoRemoteUrl,
  })  : weightKg = weightKg ?? 0.0,
        weightRecorded = weightRecorded ?? (weightKg != null);

  final int setNumber;
  final int reps;
  final double weightKg;
  final bool weightRecorded;
  final int? warningEvents;
  final String? videoLocalPath;
  final String? videoRemoteUrl;

  Map<String, dynamic> toJson() => {
        'setNumber': setNumber,
        'reps': reps,
        'weightKg': weightKg,
      };

  Map<String, dynamic> toStorageJson() => {
        'setNumber': setNumber,
        'reps': reps,
        if (weightRecorded) 'weightKg': weightKg,
        'weightRecorded': weightRecorded,
        if (warningEvents != null) 'badCount': warningEvents,
        if (videoLocalPath != null) 'videoLocalPath': videoLocalPath,
        if (videoRemoteUrl != null) 'videoRemoteUrl': videoRemoteUrl,
      };

  static bool validJsonList(Object? raw) {
    if (raw == null) return true;
    if (raw is! List) return false;
    final seen = <int>{};
    for (final value in raw) {
      if (value is! Map) return false;
      final number = value['setNumber'] ?? value['setIndex'];
      final reps = value['reps'];
      if (number is! int ||
          number < 1 ||
          !seen.add(number) ||
          reps is! int ||
          reps < 0 ||
          value.containsKey('setNumber') &&
              value.containsKey('setIndex') &&
              value['setNumber'] != value['setIndex']) {
        return false;
      }
      final weight = value['weightKg'], events = value['badCount'];
      if (weight != null &&
          (weight is! num || !weight.isFinite || weight < 0)) {
        return false;
      }
      if (events != null && (events is! int || events < 0)) return false;
    }
    return true;
  }

  static int _legacyInt(Object? value) =>
      value is num && value.isFinite ? value.toInt() : 0;
  static double? _legacyWeight(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  factory WorkoutSetDetail.fromJson(Map<String, dynamic> json,
          {bool unversionedRemote = false}) =>
      WorkoutSetDetail(
        setNumber: json.containsKey('setNumber') &&
                json.containsKey('setIndex') &&
                json['setNumber'] != json['setIndex']
            ? 0
            : _legacyInt(json['setNumber'] ?? json['setIndex']),
        reps: _legacyInt(json['reps']),
        weightKg: _legacyWeight(json['weightKg']),
        weightRecorded: json['weightRecorded'] as bool? ??
            (unversionedRemote && json['weightKg'] == 0 ? false : null),
        warningEvents:
            json['badCount'] is num ? _legacyInt(json['badCount']) : null,
        videoLocalPath: json['videoLocalPath'] is String
            ? json['videoLocalPath'] as String
            : null,
        videoRemoteUrl: json['videoRemoteUrl'] is String
            ? json['videoRemoteUrl'] as String
            : json['videoUrl'] is String
                ? json['videoUrl'] as String
                : null,
      );
}
