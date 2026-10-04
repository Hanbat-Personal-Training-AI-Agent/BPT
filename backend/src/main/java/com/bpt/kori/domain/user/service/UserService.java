package com.bpt.kori.domain.user.service;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.user.dto.DashboardSummaryResponseDto;
import com.bpt.kori.domain.user.dto.OnboardingRequest;
import com.bpt.kori.domain.user.dto.OnboardingResponse;
import com.bpt.kori.domain.user.dto.UserDto;
import com.bpt.kori.domain.user.dto.UserUpdateRequestDto;
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
    public UserDto updateProfile(Long userId, UserUpdateRequestDto request) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));

        if (request.getUsername() != null && !request.getUsername().isBlank()) {
            String newUsername = request.getUsername().trim();
            if (!newUsername.equalsIgnoreCase(user.getUsername())) {
                if (userRepository.existsByUsername(newUsername)) {
                    throw new CustomException(ErrorCode.USERNAME_ALREADY_EXISTS);
                }
                user.setUsername(newUsername);
            }
        }

        if (request.getEmail() != null && !request.getEmail().isBlank()) {
            String newEmail = request.getEmail().trim();
            if (!newEmail.equalsIgnoreCase(user.getEmail())) {
                if (userRepository.existsByEmail(newEmail)) {
                    throw new CustomException(ErrorCode.EMAIL_ALREADY_EXISTS);
                }
                user.setEmail(newEmail);
            }
        }

        if (request.getName() != null) user.setName(request.getName());
        if (request.getPhoneNumber() != null) user.setPhoneNumber(request.getPhoneNumber());
        if (request.getGender() != null) user.setGender(request.getGender());
        if (request.getHeightCm() != null && request.getHeightCm() > 0) user.setHeightCm(BigDecimal.valueOf(request.getHeightCm()));
        if (request.getWeightKg() != null && request.getWeightKg() > 0) user.setWeightKg(BigDecimal.valueOf(request.getWeightKg()));
        if (request.getWorkoutGoal() != null) user.setWorkoutGoal(request.getWorkoutGoal());
        if (request.getWeeklyFrequency() != null) user.setWeeklyFrequency(request.getWeeklyFrequency());
        if (request.getNotificationTime() != null) user.setNotificationTime(request.getNotificationTime());
        if (request.getBirthDate() != null && !request.getBirthDate().isBlank()) {
            try {
                user.setBirthDate(LocalDate.parse(request.getBirthDate().trim()));
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

        return OnboardingResponse.builder()
                .userId(user.getId())
                .isOnboardingCompleted(true)
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
        } else if (user.getLastBodyScanDate() != null) {
            daysSinceLastScan = (int) ChronoUnit.DAYS.between(user.getLastBodyScanDate(), today);
        } else {
            daysSinceLastScan = 30;
        }

        boolean needsBodyScan = daysSinceLastScan >= 30;

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
                .recentWorkouts(recentWorkouts)
                .build();
    }
}
