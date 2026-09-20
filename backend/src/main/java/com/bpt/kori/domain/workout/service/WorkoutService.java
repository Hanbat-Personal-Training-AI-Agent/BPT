package com.bpt.kori.domain.workout.service;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataRequestDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutRecordResponseDto;
import com.bpt.kori.domain.workout.entity.WorkoutFeedbackLog;
import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class WorkoutService {

    private final WorkoutRecordRepository workoutRecordRepository;
    private final UserRepository userRepository;
    private final ObjectMapper objectMapper;

    @Transactional
    public WorkoutMetadataResponseDto saveWorkoutRecord(Long userId, WorkoutMetadataRequestDto dto) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));

        // Idempotency check: if already processed by clientRecordId, return existing record
        Optional<WorkoutRecord> existing = workoutRecordRepository.findByClientRecordId(dto.getClientRecordId());
        if (existing.isPresent()) {
            WorkoutRecord record = existing.get();
            return WorkoutMetadataResponseDto.builder()
                    .serverRecordId(String.valueOf(record.getId()))
                    .clientRecordId(record.getClientRecordId())
                    .postureScore(record.getPostureScore())
                    .success(true)
                    .message("Record already synced")
                    .syncedAt(record.getCreatedAt())
                    .build();
        }

        String summaryJson = null;
        if (dto.getPoseMetricsSummary() != null) {
            try {
                summaryJson = objectMapper.writeValueAsString(dto.getPoseMetricsSummary());
            } catch (Exception e) {
                log.warn("Failed to serialize poseMetricsSummary: {}", e.getMessage());
            }
        }

        WorkoutRecord record = WorkoutRecord.builder()
                .user(user)
                .clientRecordId(dto.getClientRecordId())
                .exerciseId(dto.getExerciseId())
                .exerciseName(dto.getExerciseName())
                .date(dto.getDate() != null ? dto.getDate() : LocalDateTime.now())
                .totalReps(dto.getTotalReps())
                .correctReps(dto.getCorrectReps())
                .incorrectReps(dto.getIncorrectReps())
                .durationSeconds(dto.getDurationSeconds())
                .postureScore(dto.getPostureScore())
                .targetReps(dto.getTargetReps())
                .targetSets(dto.getTargetSets())
                .poseMetricsSummary(summaryJson)
                .build();

        if (dto.getFeedbackNotes() != null) {
            for (String note : dto.getFeedbackNotes()) {
                record.getFeedbackLogs().add(WorkoutFeedbackLog.builder()
                        .workoutRecord(record)
                        .feedbackNote(note)
                        .build());
            }
        }

        WorkoutRecord saved = workoutRecordRepository.save(record);
        user.incrementWorkoutCount();

        return WorkoutMetadataResponseDto.builder()
                .serverRecordId(String.valueOf(saved.getId()))
                .clientRecordId(saved.getClientRecordId())
                .postureScore(saved.getPostureScore())
                .success(true)
                .message("Record synced successfully")
                .syncedAt(saved.getCreatedAt())
                .build();
    }

    public List<WorkoutRecordResponseDto> getWorkoutRecords(Long userId) {
        List<WorkoutRecord> records = workoutRecordRepository.findAllByUserIdOrderByDateDesc(userId);
        return records.stream()
                .map(WorkoutRecordResponseDto::fromEntity)
                .collect(Collectors.toList());
    }
}
