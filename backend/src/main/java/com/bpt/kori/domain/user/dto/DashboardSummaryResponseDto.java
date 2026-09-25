package com.bpt.kori.domain.user.dto;

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
public class DashboardSummaryResponseDto {

    private String userName;
    private String date;
    private Double achievementRate;
    private Integer todayWorkoutMinutes;
    private Integer todayCompletedSets;
    private Integer todayTotalReps;
    private Integer weeklyGoalCount;
    private Integer weeklyCompletedCount;
    private List<String> weeklyActiveDays;
    private Boolean needsBodyScan;
    private Integer daysSinceLastScan;
    private String bodyScanAlertMessage;
    private String coachMessage;
    private List<RecentWorkoutItemDto> recentWorkouts;

    @Getter
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RecentWorkoutItemDto {
        private String exerciseName;
        private BigDecimal weightKg;
        private Integer sets;
        private Integer reps;
        private String relativeTime;
    }
}
