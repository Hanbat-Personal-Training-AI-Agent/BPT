package com.bpt.kori.domain.user.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

import java.math.BigDecimal;

@Getter
@AllArgsConstructor
@Builder
public class OnboardingResponse {

    private final Long userId;
    private final BigDecimal bmi;
    private final String bmiStatus;
    private final String bmiStatusLabel;
    private final String coachMessage;
}
