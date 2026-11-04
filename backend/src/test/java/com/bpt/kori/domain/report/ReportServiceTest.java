package com.bpt.kori.domain.report;

import com.bpt.kori.domain.report.dto.ReportAnalysisResponseDto;
import com.bpt.kori.domain.report.service.ReportService;
import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;
import static org.mockito.BDDMockito.given;

@ExtendWith(MockitoExtension.class)
class ReportServiceTest {
    @Mock private WorkoutRecordRepository repository;
    @InjectMocks private ReportService service;

    @Test
    void analysis_excludesZeroAndMissingRepsFromAllStatistics() {
        given(repository.findRecordsByUserIdAndDateRange(1L,
                LocalDate.of(2026, 9, 1).atStartOfDay(), LocalDate.of(2026, 9, 30).atTime(LocalTime.MAX)))
                .willReturn(List.of(
                        record("squat", 0, Map.of("knee", 100)),
                        record("benchpress", null, Map.of("elbow", 100)),
                        record("squat", 12, Map.of("knee", 2)),
                        record("squat", 8, Map.of("knee", 3)),
                        record("barbell-row", 1, Map.of("back", 1))));

        ReportAnalysisResponseDto result = service.getReportAnalysis(1L, "2026-09-01", "2026-09-30");

        assertThat(result.getTotalSessions()).isEqualTo(3);
        assertThat(result.getExercises()).extracting("exerciseId", "sessions")
                .containsExactly(tuple("squat", 2), tuple("barbell-row", 1));
        assertThat(result.getMistakes()).extracting("key", "count")
                .containsExactly(tuple("knee", 5), tuple("back", 1));
    }

    @Test
    void analysis_onlyZeroReps_returnsEmptyStatistics() {
        given(repository.findRecordsByUserIdAndDateRange(1L, null, null))
                .willReturn(List.of(record("squat", 0, Map.of("knee", 100))));

        ReportAnalysisResponseDto result = service.getReportAnalysis(1L, null, null);

        assertThat(result.getTotalSessions()).isZero();
        assertThat(result.getExercises()).isEmpty();
        assertThat(result.getMistakes()).isEmpty();
    }

    private WorkoutRecord record(String exerciseId, Integer reps, Map<String, Integer> mistakes) {
        return WorkoutRecord.builder().exerciseId(exerciseId).exerciseName(exerciseId)
                .totalReps(reps).feedbackCounts(mistakes).build();
    }
}
