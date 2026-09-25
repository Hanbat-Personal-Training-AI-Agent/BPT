package com.bpt.kori.domain.workout.dto;

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
public class WorkoutMetadataRequestDto {

    private String clientRecordId;
    private String exerciseId;
    private String exerciseName;
    private LocalDateTime date;
    private BigDecimal weightKg;
    private int totalReps;
    private int correctReps;
    private int incorrectReps;
    private int durationSeconds;
    private double postureScore;
    private List<String> feedbackNotes;
    private int targetReps;
    private int targetSets;
    private Map<String, Object> poseMetricsSummary;
}
