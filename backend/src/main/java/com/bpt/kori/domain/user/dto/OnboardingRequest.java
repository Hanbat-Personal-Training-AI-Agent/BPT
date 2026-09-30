package com.bpt.kori.domain.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;

@Getter
@Setter
@NoArgsConstructor
@Schema(description = "온보딩 정보 등록 요청 DTO")
public class OnboardingRequest {

    @Schema(description = "성별 (MALE, FEMALE, NOT_SPECIFIED)", example = "MALE")
    private String gender;

    @Schema(description = "신장 (cm)", example = "178.5")
    private BigDecimal heightCm;

    @Schema(description = "체중 (kg)", example = "74.0")
    private BigDecimal weightKg;

    @Schema(description = "운동 목표", example = "근력 증량")
    private String workoutGoal;

    @Schema(description = "주간 목표 운동 일수", example = "4")
    private Integer weeklyFrequency;
}
