package com.bpt.kori.domain.workout.entity;

import com.bpt.kori.domain.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

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

    @Builder.Default
    private Integer totalReps = 0;

    @Builder.Default
    private Integer correctReps = 0;

    @Builder.Default
    private Integer incorrectReps = 0;

    @Builder.Default
    private Integer durationSeconds = 0;

    @Column(nullable = false)
    @Builder.Default
    private Double postureScore = 0.0;

    @Builder.Default
    private Integer targetReps = 0;

    @Builder.Default
    private Integer targetSets = 1;

    @Column(columnDefinition = "TEXT")
    private String poseMetricsSummary;

    @OneToMany(mappedBy = "workoutRecord", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<WorkoutFeedbackLog> feedbackLogs = new ArrayList<>();

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;
}
