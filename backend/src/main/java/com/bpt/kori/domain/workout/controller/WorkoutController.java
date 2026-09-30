package com.bpt.kori.domain.workout.controller;

import com.bpt.kori.domain.workout.dto.MonthlyCalendarResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataRequestDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutRecordResponseDto;
import com.bpt.kori.domain.workout.service.WorkoutService;
import com.bpt.kori.security.UserPrincipal;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Tag(name = "Workouts", description = "운동 기록 등록, 동기화 및 캘린더 조회 API")
@RestController
@RequestMapping("/workouts")
@RequiredArgsConstructor
public class WorkoutController {

    private final WorkoutService workoutService;

    @Operation(summary = "운동 기록 저장", description = "운동 세션 완료 후 세트수, 반복수, 무게, 순수 운동시간(초), 로컬 영상 경로 등을 저장합니다.")
    @PostMapping("/records")
    public ResponseEntity<WorkoutMetadataResponseDto> submitWorkoutRecord(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestBody WorkoutMetadataRequestDto request
    ) {
        WorkoutMetadataResponseDto response = workoutService.saveWorkoutRecord(userPrincipal.getUserId(), request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @Operation(summary = "운동 기록 오프라인 동기화", description = "네트워크 재연결 시 클라이언트 레코드 ID 기준으로 중복 없이 동기화합니다.")
    @PostMapping("/records/sync")
    public ResponseEntity<WorkoutMetadataResponseDto> syncWorkoutRecord(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestBody WorkoutMetadataRequestDto request
    ) {
        WorkoutMetadataResponseDto response = workoutService.saveWorkoutRecord(userPrincipal.getUserId(), request);
        return ResponseEntity.ok(response);
    }

    @Operation(summary = "전체 운동 기록 목록 조회", description = "로그인한 사용자의 과거 운동 기록 목록을 최신순으로 조회합니다.")
    @GetMapping("/records")
    public ResponseEntity<List<WorkoutRecordResponseDto>> getWorkoutRecords(
            @AuthenticationPrincipal UserPrincipal userPrincipal
    ) {
        List<WorkoutRecordResponseDto> records = workoutService.getWorkoutRecords(userPrincipal.getUserId());
        return ResponseEntity.ok(records);
    }

    @Operation(summary = "월별 운동 캘린더 요약 조회", description = "지정한 연/월의 일별 운동 요약(운동명, 무게, 세트수, 반복수) 및 총 운동 일수를 반환합니다.")
    @GetMapping("/calendar")
    public ResponseEntity<MonthlyCalendarResponseDto> getMonthlyCalendar(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestParam(value = "year", required = false) Integer year,
            @RequestParam(value = "month", required = false) Integer month
    ) {
        MonthlyCalendarResponseDto response = workoutService.getMonthlyCalendar(userPrincipal.getUserId(), year, month);
        return ResponseEntity.ok(response);
    }
}
