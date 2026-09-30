package com.bpt.kori.domain.user.dto;

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
@Schema(description = "홈 메인 대시보드 요약 응답 DTO")
public class DashboardSummaryResponseDto {

    @Schema(description = "사용자 이름", example = "지훈")
    private String userName;

    @Schema(description = "기준 날짜 (YYYY-MM-DD)", example = "2026-09-30")
    private String date;

    @Schema(description = "주간 목표 달성률 (%)", example = "75.0")
    private Double achievementRate;

    @Schema(description = "오늘 순수 운동 시간 (분)", example = "42")
    private Integer todayWorkoutMinutes;

    @Schema(description = "오늘 완료한 세트 수", example = "4")
    private Integer todayCompletedSets;

    @Schema(description = "오늘 수행한 총 반복 횟수", example = "45")
    private Integer todayTotalReps;

    @Schema(description = "주간 목표 운동 일수", example = "4")
    private Integer weeklyGoalCount;

    @Schema(description = "이번 주 운동 완료 일수", example = "3")
    private Integer weeklyCompletedCount;

    @Schema(description = "이번 주 운동 수행 요일 목록", example = "[\"MON\", \"WED\", \"FRI\"]")
    private List<String> weeklyActiveDays;

    @Schema(description = "체형 재측정(30일 주기) 필요 여부", example = "true")
    private Boolean needsBodyScan;

    @Schema(description = "마지막 체형 측정 이후 경과 일수", example = "31")
    private Integer daysSinceLastScan;

    @Schema(description = "최근 운동 기록 리스트 (최대 2건)")
    private List<RecentWorkoutItemDto> recentWorkouts;

    @Getter
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    @Schema(description = "최근 운동 아이템 DTO")
    public static class RecentWorkoutItemDto {
        @Schema(description = "운동 이름", example = "바벨 백 스쿼트")
        private String exerciseName;

        @Schema(description = "세트 중량 (kg)", example = "60.0")
        private BigDecimal weightKg;

        @Schema(description = "세트 수", example = "4")
        private Integer sets;

        @Schema(description = "반복 횟수", example = "12")
        private Integer reps;

        @Schema(description = "상대 시간 표현", example = "오늘")
        private String relativeTime;
    }
}
