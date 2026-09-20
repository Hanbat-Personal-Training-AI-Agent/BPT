package com.bpt.kori.domain.workout.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@AllArgsConstructor
@Builder
public class WorkoutMetadataResponseDto {

    private final String serverRecordId;
    private final String clientRecordId;
    private final double postureScore;
    private final boolean success;
    private final String message;
    private final LocalDateTime syncedAt;
}
