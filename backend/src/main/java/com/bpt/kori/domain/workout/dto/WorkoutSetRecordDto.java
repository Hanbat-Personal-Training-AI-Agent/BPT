package com.bpt.kori.domain.workout.dto;

import com.bpt.kori.domain.workout.entity.WorkoutSetRecord;
import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(description = "세트별 상세 운동 기록 DTO")
public class WorkoutSetRecordDto {

    @Schema(description = "세트 순번 (1, 2, 3...)", example = "1")
    private Integer setNumber;

    @Schema(description = "반복 횟수", example = "8")
    private Integer reps;

    @Schema(description = "세트 중량 (kg)", example = "45.0")
    private Double weightKg;

    @Schema(description = "세트별 자세 상태 (안정, 주의, 위험 등)", example = "안정")
    private String postureStatus;

    public static WorkoutSetRecordDto fromEntity(WorkoutSetRecord entity) {
        if (entity == null) return null;
        return WorkoutSetRecordDto.builder()
                .setNumber(entity.getSetNumber())
                .reps(entity.getReps())
                .weightKg(entity.getWeightKg())
                .postureStatus(entity.getPostureStatus())
                .build();
    }
}
