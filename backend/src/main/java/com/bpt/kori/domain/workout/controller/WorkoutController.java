package com.bpt.kori.domain.workout.controller;

import com.bpt.kori.domain.workout.dto.MonthlyCalendarResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataRequestDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutRecordResponseDto;
import com.bpt.kori.domain.workout.service.WorkoutService;
import com.bpt.kori.security.UserPrincipal;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/workouts")
@RequiredArgsConstructor
public class WorkoutController {

    private final WorkoutService workoutService;

    @PostMapping("/records")
    public ResponseEntity<WorkoutMetadataResponseDto> submitWorkoutRecord(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestBody WorkoutMetadataRequestDto request
    ) {
        WorkoutMetadataResponseDto response = workoutService.saveWorkoutRecord(userPrincipal.getUserId(), request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PostMapping("/records/sync")
    public ResponseEntity<WorkoutMetadataResponseDto> syncWorkoutRecord(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestBody WorkoutMetadataRequestDto request
    ) {
        WorkoutMetadataResponseDto response = workoutService.saveWorkoutRecord(userPrincipal.getUserId(), request);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/records")
    public ResponseEntity<List<WorkoutRecordResponseDto>> getWorkoutRecords(
            @AuthenticationPrincipal UserPrincipal userPrincipal
    ) {
        List<WorkoutRecordResponseDto> records = workoutService.getWorkoutRecords(userPrincipal.getUserId());
        return ResponseEntity.ok(records);
    }

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
