package com.bpt.kori.domain.workout;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.workout.dto.*;
import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import com.bpt.kori.domain.workout.service.WorkoutService;
import com.fasterxml.jackson.databind.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.nio.file.*;
import java.util.*;
import java.util.function.Consumer;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class WorkoutEvidenceRoundTripTest {
    private final ObjectMapper json = new ObjectMapper().findAndRegisterModules()
            .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
    private WorkoutRecordRepository records;
    private UserRepository users;
    private WorkoutService service;
    private WorkoutRecord stored;
    private User owner;

    @BeforeEach void setup() {
        records = mock(WorkoutRecordRepository.class);
        users = mock(UserRepository.class);
        service = new WorkoutService(records, users, json);
        owner = User.builder().id(1L).username("contract-owner").build();
        when(users.findById(1L)).thenReturn(Optional.of(owner));
        when(records.findByClientRecordId(anyString())).thenAnswer(i -> Optional.ofNullable(stored));
        when(records.save(any())).thenAnswer(i -> {
            stored = i.getArgument(0); stored.setId(101L); return stored;
        });
        when(records.findAllByUserIdOrderByDateDesc(anyLong())).thenAnswer(i ->
                stored != null && stored.getUser().getId().equals(i.getArgument(0)) ? List.of(stored) : List.of());
    }

    private WorkoutMetadataRequestDto fixture() throws Exception {
        return json.readValue(Path.of("../test/fixtures/workout_evidence_v1_request.json").toFile(), WorkoutMetadataRequestDto.class);
    }
    @SuppressWarnings("unchecked")
    private Map<String, Object> evidence(WorkoutMetadataRequestDto dto) {
        return (Map<String, Object>) dto.getPoseMetricsSummary().get("workoutEvidence");
    }

    @Test void saveQueryAndActualJsonPreserveUnknownAndSeparateWarningEvents() throws Exception {
        var dto = fixture();
        service.saveWorkoutRecord(1L, dto);
        var response = service.getWorkoutRecords(1L).get(0);
        assertThat(response.getPoseMetricsSummary()).isEqualTo(dto.getPoseMetricsSummary());
        assertThat(response.getTotalReps()).isEqualTo(1);
        assertThat(response.getCorrectReps()).isZero();
        assertThat(response.getIncorrectReps()).isZero();
        assertThat(response.getFeedbackCounts()).containsEntry("pushup_hip_sag", 4).containsEntry("pushup_no_lockout", 1);
        assertThat(response.getIsGoalAchieved()).isFalse();
        assertThat(response.getTotalSets()).isEqualTo(1);
        assertThat(service.getWorkoutRecords(2L)).isEmpty();
        verify(records).findAllByUserIdOrderByDateDesc(2L);
        Path output = Path.of("build/contract-fixtures/workout-evidence-v1-response.json");
        Files.createDirectories(output.getParent());
        json.writerWithDefaultPrettyPrinter().writeValue(output.toFile(), response);
    }

    @Test void legacyCorrectnessRemainsRawAndHasNoInventedEnvelope() throws Exception {
        var dto = fixture(); dto.setPoseMetricsSummary(null); dto.setCorrectReps(1);
        service.saveWorkoutRecord(1L, dto);
        var response = service.getWorkoutRecords(1L).get(0);
        assertThat(response.getCorrectReps()).isEqualTo(1);
        assertThat(response.getPoseMetricsSummary()).isNull();
    }

    @Test void malformedOrNonObjectStoredSummaryBecomesUnknownWithoutChangingStorage() {
        for (String raw : List.of("not-json", "[1]", "true", "\"legacy-string\"", "{bad")) {
            var record = WorkoutRecord.builder().id(5L).poseMetricsSummary(raw).build();
            assertThat(WorkoutRecordResponseDto.fromEntity(record).getPoseMetricsSummary()).isNull();
            assertThat(record.getPoseMetricsSummary()).isEqualTo(raw);
        }
        var record = WorkoutRecord.builder().id(6L).poseMetricsSummary("{\"oldAngles\":[1,2]}").build();
        assertThat(WorkoutRecordResponseDto.fromEntity(record).getPoseMetricsSummary()).containsKey("oldAngles");
    }

    @Test void inconsistentOrClaimedAssessmentIsRejectedBeforePersistence() throws Exception {
        List<Consumer<WorkoutMetadataRequestDto>> changes = List.of(
            d -> evidence(d).put("version", 2), d -> evidence(d).put("version", "1"),
            d -> evidence(d).put("assessedReps", 1), d -> evidence(d).put("validatedCorrectReps", 1),
            d -> evidence(d).put("postureScore", 99), d -> evidence(d).put("formAssessment", "valid"),
            d -> evidence(d).put("completedReps", 2), d -> evidence(d).put("completedReps", 1.5),
            d -> evidence(d).put("recordedWarningEvents", -1), d -> evidence(d).put("recordedWarningEvents", 5),
            d -> d.setCorrectReps(1), d -> evidence(d).put("sets", "missing")
        );
        for (var change : changes) {
            var dto = fixture(); change.accept(dto);
            assertThatThrownBy(() -> service.saveWorkoutRecord(1L, dto)).isInstanceOf(CustomException.class)
                    .hasFieldOrPropertyWithValue("errorCode", ErrorCode.INVALID_INPUT_VALUE);
        }
        verify(records, never()).save(any());
        assertThat(owner.getTotalWorkouts()).isZero();
    }

    @Test void explicitZeroCompletedDoesNotBecomeThePlannedRepsOrSets() throws Exception {
        var dto = fixture(); dto.setTotalReps(0); dto.setWeightKg(new java.math.BigDecimal("60"));
        dto.setTargetSets(3); dto.setTotalSets(0); dto.setTotalVolume(-100);
        evidence(dto).put("completedReps", 0); evidence(dto).put("recordedWarningEvents", 0);
        evidence(dto).put("sets", List.of());
        service.saveWorkoutRecord(1L, dto);
        var response = service.getWorkoutRecords(1L).get(0);
        assertThat(response.getTotalReps()).isZero();
        assertThat(response.getTotalSets()).isZero();
        assertThat(response.getTargetSets()).isEqualTo(3);
        assertThat(response.getTotalVolume()).isZero();
        assertThat(response.getWeightKg()).isEqualByComparingTo("0");
        assertThat(response.getSetsDetail()).isEmpty();
        assertThat(response.getIsGoalAchieved()).isFalse();
    }

    @Test void missingGoalRemainsUnknownRatherThanBecomingCompletedCount() throws Exception {
        var dto = fixture(); dto.setTargetReps(null); dto.setTargetSets(null);
        service.saveWorkoutRecord(1L, dto);
        var response = service.getWorkoutRecords(1L).get(0);
        assertThat(response.getTargetReps()).isZero();
        assertThat(response.getTargetSets()).isZero();
        assertThat(response.getIsGoalAchieved()).isNull();
    }

    @Test void plannedSetsRemainIndependentOfOneActualSet() throws Exception {
        var dto = fixture(); dto.setTargetSets(3); dto.setTotalSets(1); dto.setTargetReps(1);
        service.saveWorkoutRecord(1L, dto);
        var response = service.getWorkoutRecords(1L).get(0);
        assertThat(response.getTargetSets()).isEqualTo(3);
        assertThat(response.getTotalSets()).isEqualTo(1);
        assertThat(response.getIsGoalAchieved()).isFalse();
    }

    @Test void mixedActualSetWeightsOverrideStaleVolumeAndSetDetails() throws Exception {
        var dto = fixture(); dto.setTotalReps(4); dto.setTargetSets(3); dto.setTotalSets(99);
        dto.setTotalVolume(-999); dto.setWeightKg(new java.math.BigDecimal("999"));
        var stale = new WorkoutSetRecordDto(); stale.setSetNumber(99); stale.setReps(99); stale.setWeightKg(999.0);
        dto.setSetsDetail(List.of(stale));
        evidence(dto).put("completedReps", 4);
        evidence(dto).put("sets", List.of(Map.of("reps", 1, "weightKg", 2.5, "badCount", 1),
                Map.of("reps", 3, "weightKg", 7.5, "badCount", 3)));
        service.saveWorkoutRecord(1L, dto);
        var response = service.getWorkoutRecords(1L).get(0);
        assertThat(response.getWeightKg()).isEqualByComparingTo("7.5");
        assertThat(response.getTotalVolume()).isEqualTo(25); // round(2.5+22.5), once after the sum
        assertThat(response.getTotalSets()).isEqualTo(2);
        assertThat(response.getSetsDetail()).extracting(WorkoutSetRecordDto::getReps).containsExactly(1, 3);
        assertThat(response.getSetsDetail()).extracting(WorkoutSetRecordDto::getWeightKg).containsExactly(2.5, 7.5);
        assertThat(response.getTargetSets()).isEqualTo(3);
    }

    @Test void fractionalVolumeRoundsFinalSumOnlyAndKeepsExactWeights() throws Exception {
        var dto = fixture(); dto.setTotalReps(2);
        evidence(dto).put("completedReps", 2);
        evidence(dto).put("sets", List.of(Map.of("reps", 1, "weightKg", 2.5, "badCount", 1),
                Map.of("reps", 1, "weightKg", 7.5, "badCount", 3)));
        service.saveWorkoutRecord(1L, dto);
        assertThat(service.getWorkoutRecords(1L).get(0).getTotalVolume()).isEqualTo(10);
        stored = null; // New disposable record for the next independent request.
        dto.setTotalReps(6); evidence(dto).put("completedReps", 6);
        evidence(dto).put("sets", List.of(Map.of("reps", 1, "weightKg", 2.5, "badCount", 1),
                Map.of("reps", 5, "weightKg", 5.0, "badCount", 3)));
        service.saveWorkoutRecord(1L, dto);
        var response = service.getWorkoutRecords(1L).get(0);
        assertThat(response.getTotalVolume()).isEqualTo(28); // 27.5, integer compatibility only.
        assertThat(response.getSetsDetail()).extracting(WorkoutSetRecordDto::getWeightKg).containsExactly(2.5, 5.0);
    }

    @Test void anotherOwnerCannotReadOrReplaceEvidenceUsingClientId() throws Exception {
        service.saveWorkoutRecord(1L, fixture());
        var original = stored.getPoseMetricsSummary();
        var other = User.builder().id(2L).username("other").build();
        when(users.findById(2L)).thenReturn(Optional.of(other));
        assertThatThrownBy(() -> service.saveWorkoutRecord(2L, fixture())).isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.SESSION_ACCESS_DENIED);
        assertThat(service.getWorkoutRecords(2L)).isEmpty();
        assertThat(stored.getPoseMetricsSummary()).isEqualTo(original);
        verify(records, times(1)).save(any());
    }
}
