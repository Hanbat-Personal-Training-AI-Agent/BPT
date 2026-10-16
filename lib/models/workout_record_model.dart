import 'dart:convert';
import '../data/dto/workout_metadata_dto.dart';

class WorkoutRecordModel {
  final String id; // Client side unique ID
  final String? serverId; // Spring Boot server assigned record ID
  final String exerciseId;
  final String exerciseName;
  final DateTime date;
  final double weightKg;
  final int totalReps;
  final int correctReps;
  final int incorrectReps;
  final int durationSeconds;
  final double postureScore; // 피드백 점수 (0.0 ~ 100.0)
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
    this.weightKg = 0.0,
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
  });

  int get accuracy =>
      totalReps == 0 ? 0 : ((correctReps / totalReps) * 100).round();

  int get achievement =>
      targetReps == 0 ? 100 : ((correctReps / targetReps) * 100).clamp(0.0, 100.0).round();

  /// 세트당 평균 반복 수. `totalReps` 는 전체 세트 합계라서 목록에 "N세트 × M회"
  /// 로 보여줄 때는 이 값을 쓴다.
  int get repsPerSet =>
      targetSets <= 0 ? totalReps : (totalReps / targetSets).round();

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
    int? totalReps,
    int? correctReps,
    int? incorrectReps,
    int? durationSeconds,
    double? postureScore,
    List<String>? feedbackNotes,
    int? targetReps,
    int? targetSets,
    bool? isSynced,
  }) {
    return WorkoutRecordModel(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseName: exerciseName ?? this.exerciseName,
      date: date ?? this.date,
      weightKg: weightKg ?? this.weightKg,
      totalReps: totalReps ?? this.totalReps,
      correctReps: correctReps ?? this.correctReps,
      incorrectReps: incorrectReps ?? this.incorrectReps,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      postureScore: postureScore ?? this.postureScore,
      feedbackNotes: feedbackNotes ?? this.feedbackNotes,
      targetReps: targetReps ?? this.targetReps,
      targetSets: targetSets ?? this.targetSets,
      isSynced: isSynced ?? this.isSynced,
      feedbackCounts: feedbackCounts,
    );
  }

  WorkoutMetadataRequestDto toDto() {
    return WorkoutMetadataRequestDto(
      clientRecordId: id,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      date: date,
      weightKg: weightKg,
      totalReps: totalReps,
      correctReps: correctReps,
      incorrectReps: incorrectReps,
      durationSeconds: durationSeconds,
      postureScore: postureScore,
      feedbackNotes: feedbackNotes,
      targetReps: targetReps,
      targetSets: targetSets,
      feedbackCounts: feedbackCounts,
    );
  }

  factory WorkoutRecordModel.fromDto(WorkoutMetadataRequestDto dto, {bool isSynced = false, String? serverId}) {
    return WorkoutRecordModel(
      id: dto.clientRecordId,
      serverId: serverId,
      exerciseId: dto.exerciseId,
      exerciseName: dto.exerciseName,
      date: dto.date,
      weightKg: dto.weightKg,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverId': serverId,
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
        'isSynced': isSynced,
        'feedbackCounts': feedbackCounts,
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
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0.0,
        totalReps: (json['totalReps'] as num?)?.toInt() ?? 0,
        correctReps: (json['correctReps'] as num?)?.toInt() ?? 0,
        incorrectReps: (json['incorrectReps'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        postureScore: (json['postureScore'] as num?)?.toDouble() ?? 0.0,
        feedbackNotes:
            (json['feedbackNotes'] as List?)?.cast<String>() ?? [],
        targetReps: (json['targetReps'] as num?)?.toInt() ?? 0,
        targetSets: (json['targetSets'] as num?)?.toInt() ?? 1,
        isSynced: json['isSynced'] as bool? ?? false,
        feedbackCounts: (json['feedbackCounts'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)) ??
            const {},
      );

  String toJsonString() => jsonEncode(toJson());
  factory WorkoutRecordModel.fromJsonString(String s) =>
      WorkoutRecordModel.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
