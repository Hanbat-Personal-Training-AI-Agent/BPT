package com.bpt.kori.domain.workout.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.List;

@Getter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MonthlyCalendarResponseDto {

    private Integer year;
    private Integer month;
    private Integer monthlyWorkoutCount;
    private List<String> workoutDates;
    private List<DailySummaryDto> dailySummaries;

    @Getter
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class DailySummaryDto {
        private String date;
        private List<DailyExerciseSummaryDto> records;
    }

    @Getter
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class DailyExerciseSummaryDto {
        @Schema(description = "서버 레코드 ID (운동 기록 조회 API와 동일)", example = "101")
        private String id;

        @Schema(description = "운동 종목 코드", example = "barbell-row")
        private String exerciseId;

        private String exerciseName;
        private BigDecimal weightKg;
        private Integer sets;
        private Integer reps;
    }
}
