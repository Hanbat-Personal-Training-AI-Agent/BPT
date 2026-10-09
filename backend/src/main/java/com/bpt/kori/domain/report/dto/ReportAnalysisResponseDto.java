package com.bpt.kori.domain.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.util.List;

@Getter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(description = "리포트 분석 집계 응답 DTO")
public class ReportAnalysisResponseDto {

    @Schema(description = "기간 내 총 운동 세션 수", example = "42")
    private int totalSessions;

    @Schema(description = "운동 종목별 세션 수 (세션 많은 순 정렬)")
    private List<ExerciseStatDto> exercises;

    @Schema(description = "자세 실수 유형별 발생 횟수 (발생 횟수 많은 순 정렬)")
    private List<MistakeStatDto> mistakes;

    @Getter
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    @Schema(description = "운동 종목 세션 통계")
    public static class ExerciseStatDto {
        @Schema(description = "운동 종목 코드", example = "squat")
        private String exerciseId;

        @Schema(description = "수행 세션 수", example = "13")
        private int sessions;
    }

    @Getter
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    @Schema(description = "자세 실수 통계")
    public static class MistakeStatDto {
        @Schema(description = "실수 피드백 키", example = "squat_knee_valgus")
        private String key;

        @Schema(description = "발생 누적 횟수", example = "24")
        private int count;
    }
}
