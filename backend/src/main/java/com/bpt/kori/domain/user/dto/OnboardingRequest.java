package com.bpt.kori.domain.user.dto;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;

@Getter
@Setter
@NoArgsConstructor
public class OnboardingRequest {

    private String gender; // MALE, FEMALE, NOT_SPECIFIED
    private BigDecimal heightCm;
    private BigDecimal weightKg;
    private String workoutGoal;
    private Integer weeklyFrequency;
}
