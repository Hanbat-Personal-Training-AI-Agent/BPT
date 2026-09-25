package com.bpt.kori.domain.workout.dto;

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
        private String exerciseName;
        private BigDecimal weightKg;
        private Integer sets;
        private Integer reps;
    }
}
