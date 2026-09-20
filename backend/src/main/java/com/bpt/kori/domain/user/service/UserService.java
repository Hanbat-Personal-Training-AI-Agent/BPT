package com.bpt.kori.domain.user.service;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.user.dto.OnboardingRequest;
import com.bpt.kori.domain.user.dto.OnboardingResponse;
import com.bpt.kori.domain.user.dto.UserDto;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class UserService {

    private final UserRepository userRepository;

    public UserDto getProfile(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));
        return UserDto.fromEntity(user);
    }

    @Transactional
    public UserDto updateProfile(Long userId, UserDto request) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));

        if (request.getName() != null) user.setName(request.getName());
        if (request.getGender() != null) user.setGender(request.getGender());
        if (request.getHeightCm() > 0) user.setHeightCm(BigDecimal.valueOf(request.getHeightCm()));
        if (request.getWeightKg() > 0) user.setWeightKg(BigDecimal.valueOf(request.getWeightKg()));
        if (request.getWorkoutGoal() != null) user.setWorkoutGoal(request.getWorkoutGoal());
        if (request.getBirthDate() != null) {
            try {
                user.setBirthDate(LocalDate.parse(request.getBirthDate()));
            } catch (Exception ignored) {}
        }

        return UserDto.fromEntity(user);
    }

    @Transactional
    public OnboardingResponse updateOnboarding(Long userId, OnboardingRequest request) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));

        user.updateOnboarding(
                request.getGender(),
                request.getHeightCm(),
                request.getWeightKg(),
                request.getWorkoutGoal(),
                request.getWeeklyFrequency()
        );

        // Calculate BMI: weight / (height/100)^2
        BigDecimal bmi = BigDecimal.ZERO;
        String bmiStatus = "NORMAL";
        String bmiStatusLabel = "정상 범위";

        if (request.getHeightCm() != null && request.getWeightKg() != null && request.getHeightCm().doubleValue() > 0) {
            double hM = request.getHeightCm().doubleValue() / 100.0;
            double w = request.getWeightKg().doubleValue();
            double val = w / (hM * hM);
            bmi = BigDecimal.valueOf(val).setScale(1, RoundingMode.HALF_UP);

            if (val < 18.5) {
                bmiStatus = "UNDERWEIGHT";
                bmiStatusLabel = "저체중";
            } else if (val < 23.0) {
                bmiStatus = "NORMAL";
                bmiStatusLabel = "정상 범위";
            } else if (val < 25.0) {
                bmiStatus = "OVERWEIGHT";
                bmiStatusLabel = "과체중";
            } else {
                bmiStatus = "OBESE";
                bmiStatusLabel = "비만";
            }
        }

        int freq = request.getWeeklyFrequency() != null ? request.getWeeklyFrequency() : 3;
        String goal = request.getWorkoutGoal() != null ? request.getWorkoutGoal() : "체형 관리";
        String coachMessage = String.format("주 %d회! %s 코스로 가볼까! 세트 수랑 반복 횟수는 나중에 바꿀 수 있어.", freq, goal);

        return OnboardingResponse.builder()
                .userId(user.getId())
                .bmi(bmi)
                .bmiStatus(bmiStatus)
                .bmiStatusLabel(bmiStatusLabel)
                .coachMessage(coachMessage)
                .build();
    }
}
