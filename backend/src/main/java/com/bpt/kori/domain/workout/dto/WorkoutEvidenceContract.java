package com.bpt.kori.domain.workout.dto;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Map;

/** Structural contract for the versioned, explicitly UNASSESSED native envelope. Not form validation. */
public final class WorkoutEvidenceContract {
    private static final ObjectMapper JSON = new ObjectMapper();
    private WorkoutEvidenceContract() {}

    /** Legacy summaries remain opaque and unchanged. Unsupported/new envelopes cannot claim v1 semantics. */
    public static boolean validateRequest(WorkoutMetadataRequestDto request) {
        Map<String, Object> summary = request.getPoseMetricsSummary();
        if (summary == null || !summary.containsKey("workoutEvidence")) return false;
        if (!(summary.get("workoutEvidence") instanceof Map<?, ?> e)) throw invalid();
        if (count(e.get("version")) != 1
                || !"native_scoped_rule_events".equals(e.get("source"))
                || !"delivered_rep_scope_only".equals(e.get("warningEventScope"))
                || !"not_available".equals(e.get("formAssessment"))
                || !"zero_placeholders_not_assessments".equals(e.get("legacyCorrectnessFields"))) throw invalid();
        for (String field : List.of("assessedReps", "validatedCorrectReps", "postureScore")) {
            if (!e.containsKey(field) || e.get(field) != null) throw invalid();
        }
        long completed = count(e.get("completedReps"));
        long warnings = count(e.get("recordedWarningEvents"));
        if (request.getTotalReps() != completed || request.getCorrectReps() != 0 || request.getIncorrectReps() != 0)
            throw invalid();
        if (!(e.get("sets") instanceof List<?> sets)) throw invalid();
        long repsSum = 0, eventsSum = 0;
        for (Object item : sets) {
            if (!(item instanceof Map<?, ?> set)) throw invalid();
            repsSum += count(set.get("reps"));
            eventsSum += count(set.get("badCount"));
            if (!(set.get("weightKg") instanceof Number w) || !Double.isFinite(w.doubleValue()) || w.doubleValue() < 0)
                throw invalid();
        }
        // Event counts may exceed rep counts and do not have to equal feedbackCounts (different scopes).
        if (repsSum != completed || eventsSum != warnings) throw invalid();
        return true;
    }

    private static long count(Object value) {
        if (!(value instanceof Integer || value instanceof Long)) throw invalid();
        long n = ((Number) value).longValue();
        if (n < 0 || n > Integer.MAX_VALUE) throw invalid();
        return n;
    }

    /** Never return corrupt JSON, a scalar or an array as a string disguised as metadata. */
    public static Map<String, Object> readSummary(String stored) {
        if (stored == null || stored.isBlank()) return null;
        try {
            return JSON.readValue(stored, new TypeReference<Map<String, Object>>() {});
        } catch (Exception ignored) {
            return null; // Unknown, without changing historical storage or inventing evidence.
        }
    }

    private static CustomException invalid() { return new CustomException(ErrorCode.INVALID_INPUT_VALUE); }
}
