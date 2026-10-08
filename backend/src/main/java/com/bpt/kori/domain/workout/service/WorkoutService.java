package com.bpt.kori.domain.workout.service;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.workout.dto.MonthlyCalendarResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataRequestDto;
import com.bpt.kori.domain.workout.dto.WorkoutMetadataResponseDto;
import com.bpt.kori.domain.workout.dto.WorkoutRecordResponseDto;
import com.bpt.kori.domain.workout.entity.WorkoutFeedbackLog;
import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import com.bpt.kori.domain.workout.entity.WorkoutSetRecord;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.util.*;
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
                    .videoLocalPath(record.getVideoLocalPath())
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

        int sets = dto.getEffectiveSets();
        int reps = dto.getEffectiveReps();

        int calculatedVolume = 0;
        int completedSetsCount = (dto.getTotalSets() != null && dto.getTotalSets() > 0) ? dto.getTotalSets() : sets;

        if (dto.getSetsDetail() != null && !dto.getSetsDetail().isEmpty()) {
            completedSetsCount = dto.getSetsDetail().size();
            for (var setDto : dto.getSetsDetail()) {
                double weight = setDto.getWeightKg() != null ? setDto.getWeightKg() : (dto.getWeightKg() != null ? dto.getWeightKg().doubleValue() : 0.0);
                int setReps = setDto.getReps() != null ? setDto.getReps() : 0;
                calculatedVolume += (int) (weight * setReps);
            }
        } else if (dto.getWeightKg() != null) {
            int totalReps = dto.getTotalReps() > 0 ? dto.getTotalReps() : (sets * reps);
            calculatedVolume = (int) (dto.getWeightKg().doubleValue() * totalReps);
        }

        int finalVolume = (dto.getTotalVolume() != null && dto.getTotalVolume() > 0)
                ? dto.getTotalVolume()
                : calculatedVolume;

        Boolean isGoalAchieved = dto.getIsGoalAchieved() != null
                ? dto.getIsGoalAchieved()
                : (completedSetsCount >= sets);

        WorkoutRecord record = WorkoutRecord.builder()
                .user(user)
                .clientRecordId(dto.getClientRecordId())
                .exerciseId(dto.getExerciseId())
                .exerciseName(dto.getExerciseName())
                .date(dto.getDate() != null ? dto.getDate() : LocalDateTime.now())
                .weightKg(dto.getWeightKg() != null ? dto.getWeightKg() : BigDecimal.ZERO)
                .totalReps(dto.getTotalReps() > 0 ? dto.getTotalReps() : (sets * reps))
                .correctReps(dto.getCorrectReps())
                .incorrectReps(dto.getIncorrectReps())
                .durationSeconds(dto.getDurationSeconds())
                .videoLocalPath(dto.getVideoLocalPath())
                .targetReps(reps)
                .targetSets(sets)
                .totalSets(completedSetsCount)
                .isGoalAchieved(isGoalAchieved)
                .totalVolume(finalVolume)
                .poseMetricsSummary(summaryJson)
                .build();

        if (dto.getSetsDetail() != null) {
            for (var setDto : dto.getSetsDetail()) {
                record.addSetRecord(WorkoutSetRecord.builder()
                        .setNumber(setDto.getSetNumber() != null ? setDto.getSetNumber() : 1)
                        .reps(setDto.getReps() != null ? setDto.getReps() : 0)
                        .weightKg(setDto.getWeightKg() != null ? setDto.getWeightKg() : (dto.getWeightKg() != null ? dto.getWeightKg().doubleValue() : 0.0))
                        .postureStatus(setDto.getPostureStatus())
                        .build());
            }
        }

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
                .videoLocalPath(saved.getVideoLocalPath())
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

    public MonthlyCalendarResponseDto getMonthlyCalendar(Long userId, Integer year, Integer month) {
        if (month != null && (month < 1 || month > 12)) {
            throw new CustomException(ErrorCode.INVALID_CALENDAR_MONTH);
        }

        int targetYear = year != null ? year : LocalDate.now().getYear();
        int targetMonth = month != null ? month : LocalDate.now().getMonthValue();

        LocalDateTime start = LocalDateTime.of(targetYear, targetMonth, 1, 0, 0, 0);
        int lastDay = YearMonth.of(targetYear, targetMonth).lengthOfMonth();
        LocalDateTime end = LocalDateTime.of(targetYear, targetMonth, lastDay, 23, 59, 59);

        List<WorkoutRecord> records = workoutRecordRepository.findAllByUserIdAndDateBetweenOrderByDateAsc(userId, start, end);

        DateTimeFormatter dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd");
        List<String> workoutDates = records.stream()
                .map(r -> r.getDate().format(dateFormatter))
                .distinct()
                .collect(Collectors.toList());

        Map<String, List<WorkoutRecord>> grouped = records.stream()
                .collect(Collectors.groupingBy(r -> r.getDate().format(dateFormatter), LinkedHashMap::new, Collectors.toList()));

        List<MonthlyCalendarResponseDto.DailySummaryDto> dailySummaries = new ArrayList<>();
        for (Map.Entry<String, List<WorkoutRecord>> entry : grouped.entrySet()) {
            List<MonthlyCalendarResponseDto.DailyExerciseSummaryDto> exerciseSummaries = entry.getValue().stream()
                    .map(r -> MonthlyCalendarResponseDto.DailyExerciseSummaryDto.builder()
                            .exerciseName(r.getExerciseName())
                            .weightKg(r.getWeightKg() != null ? r.getWeightKg() : BigDecimal.ZERO)
                            .sets(r.getTargetSets() != null ? r.getTargetSets() : 1)
                            .reps(r.getTargetReps() != null && r.getTargetReps() > 0 ? r.getTargetReps() : r.getTotalReps())
                            .build())
                    .collect(Collectors.toList());

            dailySummaries.add(MonthlyCalendarResponseDto.DailySummaryDto.builder()
                    .date(entry.getKey())
                    .records(exerciseSummaries)
                    .build());
        }

        return MonthlyCalendarResponseDto.builder()
                .year(targetYear)
                .month(targetMonth)
                .monthlyWorkoutCount(workoutDates.size())
                .workoutDates(workoutDates)
                .dailySummaries(dailySummaries)
                .build();
    }
}
