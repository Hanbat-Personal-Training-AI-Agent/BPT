package com.bpt.kori.domain.workout.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@Getter
@Setter
@NoArgsConstructor
@Schema(description = "운동 세션 완료 메타데이터 저장 요청 DTO")
public class WorkoutMetadataRequestDto {

    @Schema(description = "클라이언트 생성 UUID", example = "550e8400-e29b-41d4-a716-446655440000")
    private String clientRecordId;

    @Schema(description = "운동 종목 코드", example = "SQUAT")
    private String exerciseId;

    @Schema(description = "운동 이름", example = "바벨 백 스쿼트")
    private String exerciseName;

    @Schema(description = "운동 완료 일시", example = "2026-09-30T16:00:00")
    private LocalDateTime date;

    @Schema(description = "세트 중량 (kg)", example = "60.0")
    private BigDecimal weightKg;

    @Schema(description = "세트 수", example = "3")
    private Integer sets;

    @Schema(description = "목표 세트 수", example = "3")
    private Integer targetSets;

    @Schema(description = "세트당 반복 횟수", example = "12")
    private Integer reps;

    @Schema(description = "목표 반복 횟수", example = "12")
    private Integer targetReps;

    @Schema(description = "총 수행 반복 횟수", example = "36")
    private int totalReps;

    @Schema(description = "정확한 자세 반복 횟수", example = "32")
    private int correctReps;

    @Schema(description = "불완전 자세 반복 횟수", example = "4")
    private int incorrectReps;

    @Schema(description = "순수 운동 진행 시간의 총합(초단위, 휴식시간 제외)", example = "1200")
    private int durationSeconds;

    @Schema(description = "기기 내부 스토리지 녹화 영상 로컬 경로", example = "/var/mobile/Containers/Data/Application/workout_rec_01.mp4")
    private String videoLocalPath;

    @Schema(description = "자세 피드백 노트 목록")
    private List<String> feedbackNotes;

    @Schema(description = "자세 측정 통계 요약 (JSON 객체)")
    private Map<String, Object> poseMetricsSummary;

    public int getEffectiveSets() {
        if (targetSets != null && targetSets > 0) return targetSets;
        if (sets != null && sets > 0) return sets;
        return 1;
    }

    public int getEffectiveReps() {
        if (targetReps != null && targetReps > 0) return targetReps;
        if (reps != null && reps > 0) return reps;
        return totalReps;
    }
}
