package com.bpt.kori.domain.user;

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
import java.time.LocalDate;
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

    @Test
    @DisplayName("대시보드 전체 집계와 최근 운동에서 반복 없는 기록 제외")
    void getDashboardSummary_excludesRecordsWithoutReps() {
        given(userRepository.findById(1L)).willReturn(Optional.of(
                User.builder().id(1L).username("tester").weeklyFrequency(4).build()));
        LocalDate today = LocalDate.now();
        WorkoutRecord zero = dashboardRecord("미완료", today, 0, 6000, 99);
        WorkoutRecord missing = dashboardRecord("횟수 없음", today, null, 6000, 99);
        WorkoutRecord squat = dashboardRecord("스쿼트", today, 12, 120, 2);
        WorkoutRecord row = dashboardRecord("바벨로우", today, 8, 60, 1);
        // A different day containing only a zero-rep record must not count as active.
        LocalDate otherDay = today.plusDays(today.getDayOfWeek().getValue() == 7 ? -1 : 1);
        WorkoutRecord zeroOnlyDay = dashboardRecord("미완료", otherDay, 0, 6000, 99);
        given(workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(eq(1L), any(), any()))
                .willReturn(List.of(zero, missing, squat, row))
                .willReturn(List.of(zeroOnlyDay, squat, row));
        given(workoutRecordRepository.findAllByUserIdOrderByDateDesc(1L))
                .willReturn(List.of(zero, missing, squat, row));

        DashboardSummaryResponseDto result = userService.getDashboardSummary(1L);

        assertThat(result.getTodayWorkoutMinutes()).isEqualTo(3);
        assertThat(result.getTodayCompletedSets()).isEqualTo(3);
        assertThat(result.getTodayTotalReps()).isEqualTo(20);
        assertThat(result.getWeeklyCompletedCount()).isEqualTo(1);
        assertThat(result.getWeeklyActiveDays()).containsExactly(today.getDayOfWeek().name().substring(0, 3));
        assertThat(result.getAchievementRate()).isEqualTo(25.0);
        assertThat(result.getRecentWorkouts()).extracting("exerciseName")
                .containsExactly("스쿼트", "바벨로우");
    }

    @Test
    @DisplayName("주간 목표 누락 시 프로필과 대시보드 모두 3회 기준 달성률 반환")
    void getDashboardSummary_missingWeeklyGoal_defaultsToThree() {
        given(userRepository.findById(1L)).willReturn(Optional.of(
                User.builder().id(1L).username("tester").weeklyFrequency(null).build()));
        WorkoutRecord record = dashboardRecord("스쿼트", LocalDate.now(), 1, 60, 1);
        given(workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(eq(1L), any(), any()))
                .willReturn(List.of(record));

        DashboardSummaryResponseDto result = userService.getDashboardSummary(1L);

        assertThat(userService.getProfile(1L).getWeeklyFrequency()).isEqualTo(3);
        assertThat(result.getWeeklyGoalCount()).isEqualTo(3);
        assertThat(result.getAchievementRate()).isEqualTo(33.3);
    }

    @Test
    @DisplayName("미완료 기록만 있으면 대시보드 집계와 최근 운동은 비어 있음")
    void getDashboardSummary_onlyZeroReps_returnsEmptySummary() {
        given(userRepository.findById(1L)).willReturn(Optional.of(
                User.builder().id(1L).username("tester").build()));
        WorkoutRecord record = dashboardRecord("미완료", LocalDate.now(), 0, 300, 5);
        given(workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(eq(1L), any(), any()))
                .willReturn(List.of(record));
        given(workoutRecordRepository.findAllByUserIdOrderByDateDesc(1L)).willReturn(List.of(record));

        DashboardSummaryResponseDto result = userService.getDashboardSummary(1L);

        assertThat(result.getTodayWorkoutMinutes()).isZero();
        assertThat(result.getTodayCompletedSets()).isZero();
        assertThat(result.getTodayTotalReps()).isZero();
        assertThat(result.getWeeklyCompletedCount()).isZero();
        assertThat(result.getWeeklyActiveDays()).isEmpty();
        assertThat(result.getAchievementRate()).isZero();
        assertThat(result.getRecentWorkouts()).isEmpty();
    }

    private WorkoutRecord dashboardRecord(String name, LocalDate day, Integer reps, int seconds, int sets) {
        return WorkoutRecord.builder().exerciseName(name).date(day.atTime(12, 0))
                .totalReps(reps).durationSeconds(seconds).targetSets(sets).build();
    }

    @Test
    @DisplayName("프로필 수정 - 아이디 중복 시 409 예외 발생")
    void updateProfile_duplicateUsername_throwsException() {
        Long userId = 1L;
        User user = User.builder().id(userId).username("current_user").email("user@bpt.app").build();
        given(userRepository.findById(userId)).willReturn(Optional.of(user));
        given(userRepository.existsByUsername("taken_user")).willReturn(true);

        UserUpdateRequestDto request = new UserUpdateRequestDto();
        request.setUsername("taken_user");

        org.assertj.core.api.Assertions.assertThatThrownBy(() -> userService.updateProfile(userId, request))
                .isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.USERNAME_ALREADY_EXISTS);
    }

    @Test
    @DisplayName("프로필 수정 - 이메일 중복 시 409 예외 발생")
    void updateProfile_duplicateEmail_throwsException() {
        Long userId = 1L;
        User user = User.builder().id(userId).username("current_user").email("user@bpt.app").build();
        given(userRepository.findById(userId)).willReturn(Optional.of(user));
        given(userRepository.existsByEmail("taken@bpt.app")).willReturn(true);

        UserUpdateRequestDto request = new UserUpdateRequestDto();
        request.setEmail("taken@bpt.app");

        org.assertj.core.api.Assertions.assertThatThrownBy(() -> userService.updateProfile(userId, request))
                .isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.EMAIL_ALREADY_EXISTS);
    }

    @Test
    @DisplayName("프로필 수정 성공 - 정상 업데이트")
    void updateProfile_success() {
        Long userId = 1L;
        User user = User.builder().id(userId).username("current_user").email("user@bpt.app").name("홍길동").build();
        given(userRepository.findById(userId)).willReturn(Optional.of(user));
        given(userRepository.existsByUsername("new_username")).willReturn(false);

        UserUpdateRequestDto request = new UserUpdateRequestDto();
        request.setUsername("new_username");
        request.setName("김철수");
        request.setWeeklyFrequency(4);

        UserDto result = userService.updateProfile(userId, request);

        assertThat(result.getUsername()).isEqualTo("new_username");
        assertThat(result.getName()).isEqualTo("김철수");
        assertThat(result.getWeeklyFrequency()).isEqualTo(4);
    }

    @Test
    @DisplayName("온보딩 정보 등록 성공 - BMI 없이 완료 여부 반환")
    void updateOnboarding_success() {
        Long userId = 1L;
        User user = User.builder().id(userId).username("user1").build();
        given(userRepository.findById(userId)).willReturn(Optional.of(user));

        OnboardingRequest request = new OnboardingRequest();
        request.setGender("MALE");
        request.setHeightCm(BigDecimal.valueOf(180));
        request.setWeightKg(BigDecimal.valueOf(75));
        request.setWorkoutGoal("체력 증진");
        request.setWeeklyFrequency(4);

        OnboardingResponse response = userService.updateOnboarding(userId, request);

        assertThat(response).isNotNull();
        assertThat(response.getUserId()).isEqualTo(userId);
        assertThat(response.getIsOnboardingCompleted()).isTrue();
    }
}
