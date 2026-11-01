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
        assertThat(dashboard.getTodayCompletedSets()).isNull();
        assertThat(dashboard.getCompletedSetsEvidenceVersion()).isEqualTo(1);
        assertThat(dashboard.getTodayTotalReps()).isEqualTo(45);
        assertThat(dashboard.getNeedsBodyScan()).isTrue();
        assertThat(dashboard.getDaysSinceLastScan()).isGreaterThanOrEqualTo(30);
        assertThat(dashboard.getRecentWorkouts()).hasSize(1);
        assertThat(dashboard.getRecentWorkouts().get(0).getExerciseName()).isEqualTo("스쿼트");
        assertThat(dashboard.getRecentWorkouts().get(0).getWeightKg()).isEqualByComparingTo("60.0");
    }

    private DashboardSummaryResponseDto dashboardFor(List<WorkoutRecord> records) {
        given(userRepository.findById(1L)).willReturn(Optional.of(User.builder().id(1L).username("synthetic").build()));
        given(workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(eq(1L), any(), any())).willReturn(records);
        given(workoutRecordRepository.findAllByUserIdOrderByDateDesc(1L)).willReturn(records);
        return userService.getDashboardSummary(1L);
    }

    private WorkoutRecord nativeRecord() throws Exception {
        var json = new com.fasterxml.jackson.databind.ObjectMapper().findAndRegisterModules()
                .disable(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
        var dto = json.readValue(java.nio.file.Path.of("../test/fixtures/workout_evidence_v1_request.json").toFile(), com.bpt.kori.domain.workout.dto.WorkoutMetadataRequestDto.class);
        return WorkoutRecord.builder().date(LocalDateTime.now()).targetSets(3)
                .totalReps(dto.getTotalReps()).correctReps(0).incorrectReps(0)
                .poseMetricsSummary(json.writeValueAsString(dto.getPoseMetricsSummary())).build();
    }

    @Test void dashboardUsesActualOneSetDespiteThreePlanned() throws Exception {
        var response = dashboardFor(List.of(nativeRecord()));
        assertThat(response.getTodayCompletedSets()).isEqualTo(1);
        String wire = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(response);
        assertThat(wire).contains("\"completedSetsEvidenceVersion\":1", "\"todayCompletedSets\":1");
    }

    @Test void dashboardValidatedEmptyNativeSessionIsKnownZero() throws Exception {
        var record = nativeRecord();
        var json = new com.fasterxml.jackson.databind.ObjectMapper();
        var tree = json.readTree(record.getPoseMetricsSummary());
        var evidence = (com.fasterxml.jackson.databind.node.ObjectNode) tree.get("workoutEvidence");
        evidence.put("completedReps", 0); evidence.put("recordedWarningEvents", 0); evidence.putArray("sets");
        record.setTotalReps(0); record.setPoseMetricsSummary(json.writeValueAsString(tree));
        assertThat(dashboardFor(List.of(record)).getTodayCompletedSets()).isZero();
    }

    @Test void dashboardMixedLegacyRecordRemainsUnknown() throws Exception {
        var legacy = WorkoutRecord.builder().date(LocalDateTime.now()).targetSets(8).totalSets(8).totalReps(12).build();
        assertThat(dashboardFor(List.of(nativeRecord(), legacy)).getTodayCompletedSets()).isNull();
    }

    @Test void dashboardEmptyDayIsKnownZero() {
        assertThat(dashboardFor(List.of()).getTodayCompletedSets()).isZero();
    }

    @Test void dashboardExplicitSavedRowsSupplyActualCount() {
        var row = com.bpt.kori.domain.workout.entity.WorkoutSetRecord.builder().setNumber(1).reps(12).build();
        var record = WorkoutRecord.builder().date(LocalDateTime.now()).targetSets(3).totalReps(12).setRecords(List.of(row)).build();
        assertThat(dashboardFor(List.of(record)).getTodayCompletedSets()).isEqualTo(1);
    }

    @Test void invalidNativeEnvelopeCannotClaimActualSets() throws Exception {
        var record = nativeRecord(); record.setTotalReps(999);
        assertThat(dashboardFor(List.of(record)).getTodayCompletedSets()).isNull();
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
