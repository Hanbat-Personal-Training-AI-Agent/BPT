package com.bpt.kori.domain.workout.repository;

import com.bpt.kori.domain.workout.entity.WorkoutRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface WorkoutRecordRepository extends JpaRepository<WorkoutRecord, Long> {

    List<WorkoutRecord> findAllByUserIdOrderByDateDesc(Long userId);

    Optional<WorkoutRecord> findByClientRecordId(String clientRecordId);

    List<WorkoutRecord> findAllByUserIdAndDateBetweenOrderByDateAsc(
            Long userId,
            LocalDateTime start,
            LocalDateTime end
    );

    @Query("SELECT r FROM WorkoutRecord r WHERE r.user.id = :userId AND (:exerciseId IS NULL OR r.exerciseId = :exerciseId) AND r.date >= :since ORDER BY r.date ASC")
    List<WorkoutRecord> findRecordsForAnalytics(
            @Param("userId") Long userId,
            @Param("exerciseId") String exerciseId,
            @Param("since") LocalDateTime since
    );
}
