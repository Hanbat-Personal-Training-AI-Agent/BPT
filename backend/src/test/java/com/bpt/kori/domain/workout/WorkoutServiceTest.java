package com.bpt.kori.domain.workout;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.workout.dto.MonthlyCalendarResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataRequestDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutRecordResponseDto;
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
import static org.mockito.Mockito.never;

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
        request.setVideoLocalPath("/local/path/video.mp4");
        request.setTargetReps(12);
        request.setTargetSets(4);

        WorkoutRecord savedRecord = WorkoutRecord.builder()
                .id(501L)
                .clientRecordId("rec_1001")
                .user(user)
                .exerciseId("SQUAT")
                .exerciseName("바벨 백 스쿼트")
                .weightKg(new BigDecimal("60.0"))
                .videoLocalPath("/local/path/video.mp4")
                .targetSets(4)
                .targetReps(12)
                .build();

        given(workoutRecordRepository.save(any(WorkoutRecord.class))).willReturn(savedRecord);

        // when
        WorkoutMetadataResponseDto response = workoutService.saveWorkoutRecord(userId, request);

        // then
        assertThat(response.isSuccess()).isTrue();
        assertThat(response.getServerRecordId()).isEqualTo("501");
        assertThat(response.getVideoLocalPath()).isEqualTo("/local/path/video.mp4");
        verify(workoutRecordRepository).save(any(WorkoutRecord.class));
    }

    @Test
    @DisplayName("다른 사용자의 기록 ID 재사용은 거절하고 기록을 변경하지 않는다")
    void saveWorkoutRecord_otherOwner_throwsAccessDenied() {
        User requester = User.builder().id(2L).username("requester").build();
        User owner = User.builder().id(1L).username("owner").build();
        WorkoutRecord existing = WorkoutRecord.builder()
                .id(501L)
                .clientRecordId("rec_private")
                .user(owner)
                .videoLocalPath("/private/owner/video.mp4")
                .build();
        given(userRepository.findById(2L)).willReturn(Optional.of(requester));
        given(workoutRecordRepository.findByClientRecordId("rec_private"))
                .willReturn(Optional.of(existing));
        WorkoutMetadataRequestDto request = new WorkoutMetadataRequestDto();
        request.setClientRecordId("rec_private");

        assertThatThrownBy(() -> workoutService.saveWorkoutRecord(2L, request))
                .isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.SESSION_ACCESS_DENIED);
        verify(workoutRecordRepository, never()).save(any(WorkoutRecord.class));
        assertThat(requester.getTotalWorkouts()).isZero();
        assertThat(existing.getUser().getId()).isEqualTo(1L);
    }

    @Test
    @DisplayName("본인 기록 재전송은 기존 결과를 반환하고 운동 횟수를 늘리지 않는다")
    void saveWorkoutRecord_sameOwner_returnsExistingRecord() {
        User requester = User.builder().id(1000L).username("owner").build();
        // Separate entity instances must still match by persistent user ID.
        User owner = User.builder().id(Long.valueOf("1000")).username("owner").build();
        LocalDateTime createdAt = LocalDateTime.of(2026, 9, 10, 10, 0);
        WorkoutRecord existing = WorkoutRecord.builder()
                .id(501L)
                .clientRecordId("rec_existing")
                .user(owner)
                .videoLocalPath("/local/video.mp4")
                .createdAt(createdAt)
                .build();
        given(userRepository.findById(1000L)).willReturn(Optional.of(requester));
        given(workoutRecordRepository.findByClientRecordId("rec_existing"))
                .willReturn(Optional.of(existing));
        WorkoutMetadataRequestDto request = new WorkoutMetadataRequestDto();
        request.setClientRecordId("rec_existing");

        WorkoutMetadataResponseDto response = workoutService.saveWorkoutRecord(1000L, request);

        assertThat(response.isSuccess()).isTrue();
        assertThat(response.getServerRecordId()).isEqualTo("501");
        assertThat(response.getClientRecordId()).isEqualTo("rec_existing");
        assertThat(response.getVideoLocalPath()).isEqualTo("/local/video.mp4");
        assertThat(response.getSyncedAt()).isEqualTo(createdAt);
        verify(workoutRecordRepository, never()).save(any(WorkoutRecord.class));
        assertThat(requester.getTotalWorkouts()).isZero();
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
    @DisplayName("캘린더 운동일과 일별 기록에서 반복 없는 기록 제외")
    void getMonthlyCalendar_excludesRecordsWithoutReps() {
        List<WorkoutRecord> records = List.of(
                calendarRecord(1L, "squat", 9, 0),
                calendarRecord(2L, "squat", 9, null),
                calendarRecord(3L, "squat", 10, 12),
                calendarRecord(4L, "barbell-row", 10, 0),
                calendarRecord(5L, "barbell-row", 10, 8),
                calendarRecord(6L, "squat", 11, 1));
        given(workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(eq(1L), any(), any()))
                .willReturn(records);

        MonthlyCalendarResponseDto result = workoutService.getMonthlyCalendar(1L, 2026, 9);

        assertThat(result.getMonthlyWorkoutCount()).isEqualTo(2);
        assertThat(result.getWorkoutDates()).containsExactly("2026-09-10", "2026-09-11");
        assertThat(result.getDailySummaries()).extracting("date")
                .containsExactly("2026-09-10", "2026-09-11");
        assertThat(result.getDailySummaries().get(0).getRecords()).extracting("reps")
                .containsExactly(12, 8);
        assertThat(result.getDailySummaries().get(1).getRecords()).hasSize(1);
    }

    @Test
    @DisplayName("미완료 기록만 있는 달은 캘린더 운동일과 일별 목록이 비어 있음")
    void getMonthlyCalendar_onlyZeroReps_returnsEmptyCalendar() {
        given(workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(eq(1L), any(), any()))
                .willReturn(List.of(calendarRecord(1L, "squat", 10, 0)));

        MonthlyCalendarResponseDto result = workoutService.getMonthlyCalendar(1L, 2026, 9);

        assertThat(result.getMonthlyWorkoutCount()).isZero();
        assertThat(result.getWorkoutDates()).isEmpty();
        assertThat(result.getDailySummaries()).isEmpty();
    }

    @Test
    @DisplayName("캘린더 JSON에 기록 조회 API와 동일한 문자열 id와 exerciseId 제공")
    void getMonthlyCalendar_includesRecordAndExerciseIds() {
        WorkoutRecord record = calendarRecord(501L, "barbell-row", 10, 8);
        given(workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(eq(1L), any(), any()))
                .willReturn(List.of(record));
        given(workoutRecordRepository.findAllByUserIdOrderByDateDesc(1L)).willReturn(List.of(record));

        MonthlyCalendarResponseDto calendar = workoutService.getMonthlyCalendar(1L, 2026, 9);
        WorkoutRecordResponseDto detail = workoutService.getWorkoutRecords(1L).get(0);
        com.fasterxml.jackson.databind.JsonNode json = new ObjectMapper()
                .valueToTree(calendar.getDailySummaries().get(0).getRecords().get(0));

        assertThat(json.path("id").isTextual()).isTrue();
        assertThat(json.path("id").asText()).isEqualTo("501").isEqualTo(detail.getId());
        assertThat(json.path("exerciseId").asText()).isEqualTo("barbell-row").isEqualTo(detail.getExerciseId());
        assertThat(json.path("reps").asInt()).isEqualTo(8);
    }

    private WorkoutRecord calendarRecord(Long id, String exerciseId, int day, Integer reps) {
        return WorkoutRecord.builder().id(id).clientRecordId("rec_" + id)
                .exerciseId(exerciseId).exerciseName(exerciseId)
                .date(LocalDateTime.of(2026, 9, day, 12, 0)).totalReps(reps).build();
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
