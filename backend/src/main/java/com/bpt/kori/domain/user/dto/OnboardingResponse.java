package com.bpt.kori.domain.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

import java.math.BigDecimal;

@Getter
@AllArgsConstructor
@Builder
@Schema(description = "온보딩 정보 등록 응답 DTO")
public class OnboardingResponse {

    @Schema(description = "사용자 고유 ID", example = "1")
    private final Long userId;

    @Schema(description = "계산된 BMI 지수", example = "23.2")
    private final BigDecimal bmi;

    @Schema(description = "BMI 상태 코드", example = "OVERWEIGHT")
    private final String bmiStatus;

    @Schema(description = "BMI 상태 한글 라벨", example = "과체중")
    private final String bmiStatusLabel;
}
