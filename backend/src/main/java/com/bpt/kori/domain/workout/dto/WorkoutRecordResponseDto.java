package com.bpt.kori.domain.workout.dto;

import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

import java.math.BigDecimal;
import java.util.List;
import java.util.stream.Collectors;

@Getter
@AllArgsConstructor
@Builder
@Schema(description = "운동 세션 기록 상세 응답 DTO")
public class WorkoutRecordResponseDto {

    @Schema(description = "서버 레코드 ID", example = "101")
    private final String id;

    @Schema(description = "클라이언트 레코드 ID", example = "550e8400-e29b-41d4-a716-446655440000")
    private final String clientRecordId;

    @Schema(description = "운동 종목 코드", example = "SQUAT")
    private final String exerciseId;

    @Schema(description = "운동 이름", example = "바벨 백 스쿼트")
    private final String exerciseName;

    @Schema(description = "운동 일시", example = "2026-09-30T16:00:00")
    private final String date;

    @Schema(description = "세트 중량 (kg)", example = "60.0")
    private final BigDecimal weightKg;

    @Schema(description = "세트 수", example = "3")
    private final int sets;

    @Schema(description = "목표 세트 수", example = "3")
    private final int targetSets;

    @Schema(description = "세트당 반복 횟수", example = "12")
    private final int reps;

    @Schema(description = "목표 반복 횟수", example = "12")
    private final int targetReps;

    @Schema(description = "총 수행 반복 횟수", example = "36")
    private final int totalReps;

    @Schema(description = "정확한 자세 반복 횟수", example = "32")
    private final int correctReps;

    @Schema(description = "불완전 자세 반복 횟수", example = "4")
    private final int incorrectReps;

    @Schema(description = "순수 운동 진행 시간의 총합(초단위, 휴식시간 제외)", example = "1200")
    private final int durationSeconds;

    @Schema(description = "기기 내부 스토리지 녹화 영상 경로", example = "/var/mobile/Containers/Data/Application/workout_rec_01.mp4")
    private final String videoLocalPath;

    @Schema(description = "피드백 노트 목록")
    private final List<String> feedbackNotes;

    public static WorkoutRecordResponseDto fromEntity(WorkoutRecord entity) {
        List<String> notes = entity.getFeedbackLogs().stream()
                .map(log -> log.getFeedbackNote())
                .collect(Collectors.toList());

        int effectiveSets = entity.getTargetSets() != null && entity.getTargetSets() > 0 ? entity.getTargetSets() : 1;
        int effectiveReps = entity.getTargetReps() != null && entity.getTargetReps() > 0 ? entity.getTargetReps() :
                (entity.getTotalReps() != null ? entity.getTotalReps() : 0);

        return WorkoutRecordResponseDto.builder()
                .id(String.valueOf(entity.getId()))
                .clientRecordId(entity.getClientRecordId())
                .exerciseId(entity.getExerciseId())
                .exerciseName(entity.getExerciseName())
                .date(entity.getDate() != null ? entity.getDate().toString() : "")
                .weightKg(entity.getWeightKg() != null ? entity.getWeightKg() : BigDecimal.ZERO)
                .sets(effectiveSets)
                .targetSets(effectiveSets)
                .reps(effectiveReps)
                .targetReps(effectiveReps)
                .totalReps(entity.getTotalReps() != null ? entity.getTotalReps() : 0)
                .correctReps(entity.getCorrectReps() != null ? entity.getCorrectReps() : 0)
                .incorrectReps(entity.getIncorrectReps() != null ? entity.getIncorrectReps() : 0)
                .durationSeconds(entity.getDurationSeconds() != null ? entity.getDurationSeconds() : 0)
                .videoLocalPath(entity.getVideoLocalPath())
                .feedbackNotes(notes)
                .build();
    }
}
