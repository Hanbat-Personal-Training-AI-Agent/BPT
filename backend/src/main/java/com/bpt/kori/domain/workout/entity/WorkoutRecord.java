package com.bpt.kori.domain.workout.entity;

import com.bpt.kori.domain.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "workout_records")
@Getter
@Setter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
@EntityListeners(AuditingEntityListener.class)
public class WorkoutRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(nullable = false, unique = true, length = 64)
    private String clientRecordId;

    @Column(length = 64)
    private String exerciseId;

    @Column(nullable = false, length = 100)
    private String exerciseName;

    @Column(nullable = false)
    private LocalDateTime date;

    @Column(precision = 5, scale = 2)
    @Builder.Default
    private BigDecimal weightKg = BigDecimal.ZERO;

    @Builder.Default
    private Integer totalReps = 0;

    @Builder.Default
    private Integer correctReps = 0;

    @Builder.Default
    private Integer incorrectReps = 0;

    @Builder.Default
    private Integer durationSeconds = 0; // 휴식 시간을 제외한 순수 운동 진행 시간의 총합

    @Column(length = 500)
    private String videoLocalPath; // 기기 내부 스토리지 녹화 영상 경로

    @Builder.Default
    private Integer targetReps = 0;

    @Builder.Default
    private Integer targetSets = 1;

    @Builder.Default
    private Integer totalSets = 0;

    @Builder.Default
    private Boolean isGoalAchieved = false;

    @Builder.Default
    private Integer totalVolume = 0;

    @Column(columnDefinition = "TEXT")
    private String poseMetricsSummary;

    @OneToMany(mappedBy = "workoutRecord", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<WorkoutSetRecord> setRecords = new ArrayList<>();

    @OneToMany(mappedBy = "workoutRecord", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<WorkoutFeedbackLog> feedbackLogs = new ArrayList<>();

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    public void addSetRecord(WorkoutSetRecord setRecord) {
        if (setRecords == null) {
            setRecords = new ArrayList<>();
        }
        setRecords.add(setRecord);
        setRecord.setWorkoutRecord(this);
    }
}
