package com.bpt.kori.domain.workout;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.workout.dto.MonthlyCalendarResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataRequestDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataResponseDto;
import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import com.bpt.kori.domain.workout.service.WorkoutService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class WorkoutServiceTest {

    @Mock
    private WorkoutRecordRepository workoutRecordRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private ObjectMapper objectMapper;

    @InjectMocks
    private WorkoutService workoutService;

    @Test
    @DisplayName("[API 7 & 8] 운동 기록 세트별 중량(weightKg) 포함 저장 성공")
    void saveWorkoutRecord_withWeightKg() {
        // given
        Long userId = 1L;
        User user = User.builder().id(userId).username("testuser").build();
        given(userRepository.findById(userId)).willReturn(Optional.of(user));
        given(workoutRecordRepository.findByClientRecordId("rec_1001")).willReturn(Optional.empty());

        WorkoutMetadataRequestDto request = new WorkoutMetadataRequestDto();
        request.setClientRecordId("rec_1001");
        request.setExerciseId("SQUAT");
        request.setExerciseName("바벨 백 스쿼트");
        request.setDate(LocalDateTime.now());
        request.setWeightKg(new BigDecimal("60.0"));
        request.setTotalReps(45);
        request.setCorrectReps(38);
        request.setIncorrectReps(7);
        request.setDurationSeconds(1800);
        request.setPostureScore(88.5);
        request.setTargetReps(12);
        request.setTargetSets(4);

        WorkoutRecord savedRecord = WorkoutRecord.builder()
                .id(501L)
                .clientRecordId("rec_1001")
                .user(user)
                .exerciseId("SQUAT")
                .exerciseName("바벨 백 스쿼트")
                .weightKg(new BigDecimal("60.0"))
                .postureScore(88.5)
                .build();

        given(workoutRecordRepository.save(any(WorkoutRecord.class))).willReturn(savedRecord);

        // when
        WorkoutMetadataResponseDto response = workoutService.saveWorkoutRecord(userId, request);

        // then
        assertThat(response.isSuccess()).isTrue();
        assertThat(response.getServerRecordId()).isEqualTo("501");
        assertThat(response.getPostureScore()).isEqualTo(88.5);
        verify(workoutRecordRepository).save(any(WorkoutRecord.class));
    }

    @Test
    @DisplayName("[API 13] 월간 캘린더 조회 성공")
    void getMonthlyCalendar_success() {
        // given
        Long userId = 1L;
        LocalDateTime date1 = LocalDateTime.of(2026, 9, 10, 10, 0);
        WorkoutRecord record = WorkoutRecord.builder()
                .id(1L)
                .exerciseName("바벨 백 스쿼트")
                .weightKg(new BigDecimal("60.0"))
                .date(date1)
                .targetSets(4)
                .targetReps(12)
                .totalReps(12)
                .build();

        given(workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(eq(userId), any(), any()))
                .willReturn(List.of(record));

        // when
        MonthlyCalendarResponseDto result = workoutService.getMonthlyCalendar(userId, 2026, 9);

        // then
        assertThat(result.getYear()).isEqualTo(2026);
        assertThat(result.getMonth()).isEqualTo(9);
        assertThat(result.getMonthlyWorkoutCount()).isEqualTo(1);
        assertThat(result.getWorkoutDates()).containsExactly("2026-09-10");
        assertThat(result.getDailySummaries()).hasSize(1);
        assertThat(result.getDailySummaries().get(0).getDate()).isEqualTo("2026-09-10");
        assertThat(result.getDailySummaries().get(0).getRecords().get(0).getWeightKg()).isEqualByComparingTo("60.0");
    }

    @Test
    @DisplayName("[API 13] 월간 캘린더 조회 시 잘못된 월 입력 시 예외 발생")
    void getMonthlyCalendar_invalidMonth_throwsException() {
        Long userId = 1L;

        assertThatThrownBy(() -> workoutService.getMonthlyCalendar(userId, 2026, 13))
                .isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.INVALID_CALENDAR_MONTH);
    }
}
