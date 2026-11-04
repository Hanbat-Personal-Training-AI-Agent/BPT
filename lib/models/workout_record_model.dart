import 'dart:convert';
import '../data/dto/workout_metadata_dto.dart';
import '../features/workout/data/workout_evidence.dart';
import '../features/workout/data/workout_result_evidence.dart';

class WorkoutRecordModel {
  final String id; // Client side unique ID
  final String? serverId; // Spring Boot server assigned record ID
  final String exerciseId;
  final String exerciseName;
  final DateTime date;
  final double weightKg;
  final bool weightRecorded;
  final List<WorkoutSetDetail> setsDetail;
  final bool setsDetailValid;
  final int totalReps;
  final int correctReps;
  final int incorrectReps;
  final int durationSeconds;
  final double?
      postureScore; // Raw legacy value; not independently validated form evidence.
  final Map<String, dynamic> poseMetricsSummary;
  final List<String> feedbackNotes;
  final int targetReps;
  final int targetSets;
  final bool isSynced; // Spring Boot 백엔드 서버 동기화 여부

  /// 자세 피드백 키별 횟수 (kori_feedback_lines.dart 키). 리포트 "자주 나온 실수" 집계용.
  final Map<String, int> feedbackCounts;

  const WorkoutRecordModel({
    required this.id,
    this.serverId,
    required this.exerciseId,
    required this.exerciseName,
    required this.date,
    double? weightKg,
    bool? weightRecorded,
    this.setsDetail = const [],
    this.setsDetailValid = true,
    required this.totalReps,
    required this.correctReps,
    required this.incorrectReps,
    required this.durationSeconds,
    required this.postureScore,
    required this.feedbackNotes,
    this.targetReps = 0,
    this.targetSets = 1,
    this.isSynced = false,
    this.feedbackCounts = const {},
    this.poseMetricsSummary = const {},
  })  : weightKg = weightKg ?? 0.0,
        weightRecorded = weightRecorded ?? (weightKg != null);

  /// No current producer supplies independently validated correct-form rep evidence.
  int? get accuracy => null;
  double? get assessedPostureScore => null;
  int? get achievement =>
      WorkoutEvidence.completionPercent(totalReps, targetReps);

  Map<String, dynamic> get resultEvidenceFields => {
        'poseMetricsSummary': poseMetricsSummary,
        'setResultsValid': setsDetailValid,
        if (weightRecorded) 'weightKg': weightKg,
        if (setsDetail.isNotEmpty)
          'setResults': setsDetail.map((set) => set.toStorageJson()).toList(),
      };

  WorkoutResultEvidence get _resultEvidence =>
      WorkoutResultEvidence.fromResult({
        ...resultEvidenceFields,
        'totalReps': totalReps,
      });

  /// Actual recorded sets come from a matching list, never from a target goal.
  int? get completedSets => _resultEvidence.completedSets;

  /// Only a uniform observed set list has one reps-per-set value. Mixed/legacy unknown is not an average.
  int? get repsPerSet {
    final evidence = _resultEvidence;
    if (!evidence.completeBreakdown || evidence.sets.isEmpty) return null;
    final counts = evidence.sets.map((s) => s.reps).toSet();
    return counts.length == 1 ? counts.single : null;
  }

  String get durationFormatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m}m ${s}s';
  }

  WorkoutRecordModel copyWith({
    String? id,
    String? serverId,
    String? exerciseId,
    String? exerciseName,
    DateTime? date,
    double? weightKg,
    bool? weightRecorded,
    List<WorkoutSetDetail>? setsDetail,
    bool? setsDetailValid,
    int? totalReps,
    int? correctReps,
    int? incorrectReps,
    int? durationSeconds,
    double? postureScore,
    bool clearPostureScore = false,
    List<String>? feedbackNotes,
    int? targetReps,
    int? targetSets,
    bool? isSynced,
    Map<String, dynamic>? poseMetricsSummary,
    Map<String, int>? feedbackCounts,
  }) {
    return WorkoutRecordModel(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseName: exerciseName ?? this.exerciseName,
      date: date ?? this.date,
      weightKg: weightKg ?? this.weightKg,
      weightRecorded:
          weightRecorded ?? (weightKg != null ? true : this.weightRecorded),
      setsDetail: setsDetail ?? this.setsDetail,
      setsDetailValid: setsDetailValid ?? this.setsDetailValid,
      totalReps: totalReps ?? this.totalReps,
      correctReps: correctReps ?? this.correctReps,
      incorrectReps: incorrectReps ?? this.incorrectReps,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      postureScore:
          clearPostureScore ? null : postureScore ?? this.postureScore,
      feedbackNotes: feedbackNotes ?? this.feedbackNotes,
      targetReps: targetReps ?? this.targetReps,
      targetSets: targetSets ?? this.targetSets,
      isSynced: isSynced ?? this.isSynced,
      feedbackCounts: feedbackCounts ?? this.feedbackCounts,
      poseMetricsSummary: poseMetricsSummary ?? this.poseMetricsSummary,
    );
  }

  WorkoutMetadataRequestDto toDto() {
    return WorkoutMetadataRequestDto(
      clientRecordId: id,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      date: date,
      weightKg: weightKg,
      weightRecorded: weightRecorded,
      setsDetail: setsDetail,
      setsDetailValid: setsDetailValid,
      totalReps: totalReps,
      correctReps: correctReps,
      incorrectReps: incorrectReps,
      durationSeconds: durationSeconds,
      postureScore: postureScore,
      feedbackNotes: feedbackNotes,
      targetReps: targetReps,
      targetSets: targetSets,
      feedbackCounts: feedbackCounts,
      poseMetricsSummary: poseMetricsSummary,
    );
  }

  factory WorkoutRecordModel.fromDto(WorkoutMetadataRequestDto dto,
      {bool isSynced = false, String? serverId}) {
    return WorkoutRecordModel(
      id: dto.clientRecordId,
      serverId: serverId,
      exerciseId: dto.exerciseId,
      exerciseName: dto.exerciseName,
      date: dto.date,
      weightKg: dto.effectiveWeightKg,
      weightRecorded: dto.effectiveWeightRecorded,
      setsDetail: dto.effectiveSetsDetail,
      setsDetailValid: dto.effectiveSetsDetailValid,
      totalReps: dto.totalReps,
      correctReps: dto.correctReps,
      incorrectReps: dto.incorrectReps,
      durationSeconds: dto.durationSeconds,
      postureScore: dto.postureScore,
      feedbackNotes: dto.feedbackNotes,
      targetReps: dto.targetReps,
      targetSets: dto.targetSets,
      isSynced: isSynced,
      feedbackCounts: dto.feedbackCounts,
      poseMetricsSummary: dto.poseMetricsSummary ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverId': serverId,
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'date': date.toIso8601String(),
        'weightKg': weightKg,
        'weightRecorded': weightRecorded,
        'setsDetail': setsDetail.map((set) => set.toStorageJson()).toList(),
        'setsDetailValid': setsDetailValid,
        'totalReps': totalReps,
        'correctReps': correctReps,
        'incorrectReps': incorrectReps,
        'durationSeconds': durationSeconds,
        'postureScore': postureScore,
        'feedbackNotes': feedbackNotes,
        'targetReps': targetReps,
        'targetSets': targetSets,
        'isSynced': isSynced,
        'feedbackCounts': feedbackCounts,
        'poseMetricsSummary': poseMetricsSummary,
      };

  factory WorkoutRecordModel.fromJson(Map<String, dynamic> json) =>
      WorkoutRecordModel(
        id: json['id'] as String? ?? '',
        serverId: json['serverId'] as String?,
        exerciseId: json['exerciseId'] as String? ?? '',
        exerciseName: json['exerciseName'] as String? ?? '',
        date: json['date'] != null
            ? DateTime.parse(json['date'] as String)
            : DateTime.now(),
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        // Old unmarked zero may be the historical missing-value fallback.
        weightRecorded: json['weightRecorded'] as bool? ??
            (json['weightKg'] == 0 ? false : null),
        setsDetail: json['setsDetail'] is List
            ? (json['setsDetail'] as List)
                .whereType<Map>()
                .map((set) => WorkoutSetDetail.fromJson(
                    set.cast<String, dynamic>(),
                    unversionedRemote: true))
                .toList()
            : const [],
        setsDetailValid: json['setsDetailValid'] != false &&
            WorkoutSetDetail.validJsonList(json['setsDetail']),
        totalReps: (json['totalReps'] as num?)?.toInt() ?? 0,
        correctReps: (json['correctReps'] as num?)?.toInt() ?? 0,
        incorrectReps: (json['incorrectReps'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        postureScore: (json['postureScore'] as num?)?.toDouble(),
        feedbackNotes: (json['feedbackNotes'] as List?)?.cast<String>() ?? [],
        targetReps: (json['targetReps'] as num?)?.toInt() ?? 0,
        targetSets: (json['targetSets'] as num?)?.toInt() ?? 1,
        isSynced: json['isSynced'] as bool? ?? false,
        poseMetricsSummary:
            WorkoutEvidence.summaryObject(json['poseMetricsSummary']) ??
                const {},
        feedbackCounts: (json['feedbackCounts'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)) ??
            const {},
      );

  String toJsonString() => jsonEncode(toJson());
  factory WorkoutRecordModel.fromJsonString(String s) =>
      WorkoutRecordModel.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
