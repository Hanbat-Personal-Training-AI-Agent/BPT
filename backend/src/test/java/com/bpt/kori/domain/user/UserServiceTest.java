package com.bpt.kori.domain.user;

import com.bpt.kori.domain.user.dto.DashboardSummaryResponseDto;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.entity.UserCalibration;
import com.bpt.kori.domain.user.repository.UserCalibrationRepository;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.user.service.UserService;
import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;

@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private WorkoutRecordRepository workoutRecordRepository;

    @Mock
    private UserCalibrationRepository userCalibrationRepository;

    @InjectMocks
    private UserService userService;

    @Test
    @DisplayName("[API 12] 메인 홈 대시보드 요약 조회 성공")
    void getDashboardSummary_success() {
        // given
        Long userId = 1L;
        User user = User.builder()
                .id(userId)
                .username("jihoon_kim")
                .name("지훈")
                .weeklyFrequency(5)
                .build();

        given(userRepository.findById(userId)).willReturn(Optional.of(user));

        LocalDateTime now = LocalDateTime.now();
        WorkoutRecord todayRecord = WorkoutRecord.builder()
                .id(10L)
                .exerciseName("스쿼트")
                .weightKg(new BigDecimal("60.0"))
                .date(now)
                .targetSets(4)
                .totalReps(45)
                .durationSeconds(2520) // 42 minutes
                .build();

        given(workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(eq(userId), any(), any()))
                .willReturn(List.of(todayRecord));
        given(workoutRecordRepository.findAllByUserIdOrderByDateDesc(userId))
                .willReturn(List.of(todayRecord));

        UserCalibration calibration = UserCalibration.builder()
                .id(1L)
                .calibratedAt(now.minusDays(30))
                .build();
        given(userCalibrationRepository.findTopByUserIdOrderByCalibratedAtDesc(userId))
                .willReturn(Optional.of(calibration));

        // when
        DashboardSummaryResponseDto dashboard = userService.getDashboardSummary(userId);

        // then
        assertThat(dashboard).isNotNull();
        assertThat(dashboard.getUserName()).isEqualTo("지훈");
        assertThat(dashboard.getWeeklyGoalCount()).isEqualTo(5);
        assertThat(dashboard.getTodayWorkoutMinutes()).isEqualTo(42);
        assertThat(dashboard.getTodayCompletedSets()).isEqualTo(4);
        assertThat(dashboard.getTodayTotalReps()).isEqualTo(45);
        assertThat(dashboard.getNeedsBodyScan()).isTrue();
        assertThat(dashboard.getDaysSinceLastScan()).isGreaterThanOrEqualTo(30);
        assertThat(dashboard.getRecentWorkouts()).hasSize(1);
        assertThat(dashboard.getRecentWorkouts().get(0).getExerciseName()).isEqualTo("스쿼트");
        assertThat(dashboard.getRecentWorkouts().get(0).getWeightKg()).isEqualByComparingTo("60.0");
    }
}
