package com.bpt.kori.domain.user.service;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.user.dto.DashboardSummaryResponseDto;
import com.bpt.kori.domain.user.dto.OnboardingRequest;
import com.bpt.kori.domain.user.dto.OnboardingResponse;
import com.bpt.kori.domain.user.dto.UserDto;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.entity.UserCalibration;
import com.bpt.kori.domain.user.repository.UserCalibrationRepository;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.temporal.ChronoUnit;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class UserService {

    private final UserRepository userRepository;
    private final WorkoutRecordRepository workoutRecordRepository;
    private final UserCalibrationRepository userCalibrationRepository;

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

    public DashboardSummaryResponseDto getDashboardSummary(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));

        String userName = user.getName() != null && !user.getName().isBlank() ? user.getName() : user.getUsername();
        int weeklyGoal = user.getWeeklyFrequency() != null ? user.getWeeklyFrequency() : 5;

        LocalDate today = LocalDate.now();
        LocalDateTime todayStart = today.atStartOfDay();
        LocalDateTime todayEnd = today.atTime(LocalTime.MAX);

        List<WorkoutRecord> todayRecords = workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(userId, todayStart, todayEnd);

        int todayWorkoutMinutes = todayRecords.stream()
                .mapToInt(r -> r.getDurationSeconds() != null ? r.getDurationSeconds() : 0)
                .sum() / 60;
        int todayCompletedSets = todayRecords.stream()
                .mapToInt(r -> r.getTargetSets() != null ? r.getTargetSets() : 1)
                .sum();
        int todayTotalReps = todayRecords.stream()
                .mapToInt(r -> r.getTotalReps() != null ? r.getTotalReps() : 0)
                .sum();

        // This week calculation (Monday to Sunday)
        LocalDate monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        LocalDate sunday = today.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY));
        List<WorkoutRecord> weekRecords = workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(
                userId, monday.atStartOfDay(), sunday.atTime(LocalTime.MAX));

        List<String> weeklyActiveDays = weekRecords.stream()
                .map(r -> {
                    DayOfWeek dow = r.getDate().getDayOfWeek();
                    switch (dow) {
                        case MONDAY: return "MON";
                        case TUESDAY: return "TUE";
                        case WEDNESDAY: return "WED";
                        case THURSDAY: return "THU";
                        case FRIDAY: return "FRI";
                        case SATURDAY: return "SAT";
                        case SUNDAY: return "SUN";
                        default: return dow.name();
                    }
                })
                .distinct()
                .collect(Collectors.toList());

        int weeklyCompletedCount = weeklyActiveDays.size();
        double achievementRate = weeklyGoal > 0
                ? Math.min(100.0, Math.round(((double) weeklyCompletedCount / weeklyGoal) * 100.0 * 10.0) / 10.0)
                : 0.0;

        // Body scan calibration status
        Optional<UserCalibration> latestCalibration = userCalibrationRepository.findTopByUserIdOrderByCalibratedAtDesc(userId);
        int daysSinceLastScan;
        if (latestCalibration.isPresent() && latestCalibration.get().getCalibratedAt() != null) {
            daysSinceLastScan = (int) ChronoUnit.DAYS.between(latestCalibration.get().getCalibratedAt().toLocalDate(), today);
        } else {
            daysSinceLastScan = 30;
        }

        boolean needsBodyScan = daysSinceLastScan >= 30;
        String bodyScanAlertMessage = needsBodyScan
                ? String.format("체형 다시 확인할 때야! 마지막 측정 후 %d일이 지났어", daysSinceLastScan)
                : null;

        String coachMessage = "오늘 무슨 운동을 할까? 바로 시작해보자!";

        List<WorkoutRecord> allRecent = workoutRecordRepository.findAllByUserIdOrderByDateDesc(userId);
        List<DashboardSummaryResponseDto.RecentWorkoutItemDto> recentWorkouts = allRecent.stream()
                .limit(2)
                .map(r -> {
                    LocalDate recordDate = r.getDate().toLocalDate();
                    long diffDays = ChronoUnit.DAYS.between(recordDate, today);
                    String relativeTime;
                    if (diffDays == 0) {
                        relativeTime = "오늘";
                    } else if (diffDays == 1) {
                        relativeTime = "어제";
                    } else {
                        relativeTime = diffDays + "일 전";
                    }

                    return DashboardSummaryResponseDto.RecentWorkoutItemDto.builder()
                            .exerciseName(r.getExerciseName())
                            .weightKg(r.getWeightKg() != null ? r.getWeightKg() : BigDecimal.ZERO)
                            .sets(r.getTargetSets() != null ? r.getTargetSets() : 1)
                            .reps(r.getTargetReps() != null && r.getTargetReps() > 0 ? r.getTargetReps() : r.getTotalReps())
                            .relativeTime(relativeTime)
                            .build();
                })
                .collect(Collectors.toList());

        return DashboardSummaryResponseDto.builder()
                .userName(userName)
                .date(today.toString())
                .achievementRate(achievementRate)
                .todayWorkoutMinutes(todayWorkoutMinutes)
                .todayCompletedSets(todayCompletedSets)
                .todayTotalReps(todayTotalReps)
                .weeklyGoalCount(weeklyGoal)
                .weeklyCompletedCount(weeklyCompletedCount)
                .weeklyActiveDays(weeklyActiveDays)
                .needsBodyScan(needsBodyScan)
                .daysSinceLastScan(daysSinceLastScan)
                .bodyScanAlertMessage(bodyScanAlertMessage)
                .coachMessage(coachMessage)
                .recentWorkouts(recentWorkouts)
                .build();
    }
}
