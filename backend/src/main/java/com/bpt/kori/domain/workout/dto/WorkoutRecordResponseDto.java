package com.bpt.kori.domain.workout.dto;

import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

import java.util.List;
import java.util.stream.Collectors;

@Getter
@AllArgsConstructor
@Builder
public class WorkoutRecordResponseDto {

    private final String id;
    private final String clientRecordId;
    private final String exerciseId;
    private final String exerciseName;
    private final String date;
    private final int totalReps;
    private final int correctReps;
    private final int incorrectReps;
    private final int durationSeconds;
    private final double postureScore;
    private final List<String> feedbackNotes;
    private final int targetReps;
    private final int targetSets;

    public static WorkoutRecordResponseDto fromEntity(WorkoutRecord entity) {
        List<String> notes = entity.getFeedbackLogs().stream()
                .map(log -> log.getFeedbackNote())
                .collect(Collectors.toList());

        return WorkoutRecordResponseDto.builder()
                .id(String.valueOf(entity.getId()))
                .clientRecordId(entity.getClientRecordId())
                .exerciseId(entity.getExerciseId())
                .exerciseName(entity.getExerciseName())
                .date(entity.getDate().toString())
                .totalReps(entity.getTotalReps() != null ? entity.getTotalReps() : 0)
                .correctReps(entity.getCorrectReps() != null ? entity.getCorrectReps() : 0)
                .incorrectReps(entity.getIncorrectReps() != null ? entity.getIncorrectReps() : 0)
                .durationSeconds(entity.getDurationSeconds() != null ? entity.getDurationSeconds() : 0)
                .postureScore(entity.getPostureScore() != null ? entity.getPostureScore() : 0.0)
                .feedbackNotes(notes)
                .targetReps(entity.getTargetReps() != null ? entity.getTargetReps() : 0)
                .targetSets(entity.getTargetSets() != null ? entity.getTargetSets() : 1)
                .build();
    }
}
