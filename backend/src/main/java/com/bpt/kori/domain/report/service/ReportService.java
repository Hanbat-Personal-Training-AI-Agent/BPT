package com.bpt.kori.domain.report.service;

import com.bpt.kori.domain.report.dto.ReportAnalysisResponseDto;
import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ReportService {

    private final WorkoutRecordRepository workoutRecordRepository;

    public ReportAnalysisResponseDto getReportAnalysis(Long userId, String from, String to) {
        LocalDateTime startDateTime = null;
        LocalDateTime endDateTime = null;

        if (from != null && !from.isBlank()) {
            try {
                startDateTime = LocalDate.parse(from.trim()).atStartOfDay();
            } catch (Exception e) {
                log.warn("Invalid from date format: {}", from);
            }
        }

        if (to != null && !to.isBlank()) {
            try {
                endDateTime = LocalDate.parse(to.trim()).atTime(LocalTime.MAX);
            } catch (Exception e) {
                log.warn("Invalid to date format: {}", to);
            }
        }

        List<WorkoutRecord> records = workoutRecordRepository.findRecordsByUserIdAndDateRange(
                userId, startDateTime, endDateTime);

        int totalSessions = records.size();

        // 1. Group by exerciseId and count sessions
        Map<String, Integer> exerciseCounts = new HashMap<>();
        for (WorkoutRecord record : records) {
            String exId = record.getExerciseId();
            if (exId == null || exId.isBlank()) {
                exId = record.getExerciseName();
            }
            if (exId != null && !exId.isBlank()) {
                exerciseCounts.merge(exId.toLowerCase(), 1, Integer::sum);
            }
        }

        List<ReportAnalysisResponseDto.ExerciseStatDto> exercises = exerciseCounts.entrySet().stream()
                .sorted((e1, e2) -> {
                    int cmp = Integer.compare(e2.getValue(), e1.getValue());
                    return cmp != 0 ? cmp : e1.getKey().compareTo(e2.getKey());
                })
                .map(e -> ReportAnalysisResponseDto.ExerciseStatDto.builder()
                        .exerciseId(e.getKey())
                        .sessions(e.getValue())
                        .build())
                .collect(Collectors.toList());

        // 2. Sum mistakes by feedback key
        Map<String, Integer> mistakeCounts = new HashMap<>();
        for (WorkoutRecord record : records) {
            Map<String, Integer> counts = record.getFeedbackCounts();
            if (counts != null) {
                for (Map.Entry<String, Integer> entry : counts.entrySet()) {
                    String key = entry.getKey();
                    Integer count = entry.getValue();
                    if (key != null && !key.isBlank() && count != null && count > 0) {
                        mistakeCounts.merge(key, count, Integer::sum);
                    }
                }
            }
        }

        List<ReportAnalysisResponseDto.MistakeStatDto> mistakes = mistakeCounts.entrySet().stream()
                .sorted((m1, m2) -> {
                    int cmp = Integer.compare(m2.getValue(), m1.getValue());
                    return cmp != 0 ? cmp : m1.getKey().compareTo(m2.getKey());
                })
                .map(m -> ReportAnalysisResponseDto.MistakeStatDto.builder()
                        .key(m.getKey())
                        .count(m.getValue())
                        .build())
                .collect(Collectors.toList());

        return ReportAnalysisResponseDto.builder()
                .totalSessions(totalSessions)
                .exercises(exercises)
                .mistakes(mistakes)
                .build();
    }
}
