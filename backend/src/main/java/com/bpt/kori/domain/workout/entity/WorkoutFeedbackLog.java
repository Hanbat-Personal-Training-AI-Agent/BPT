package com.bpt.kori.domain.workout.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "workout_feedback_logs")
@Getter
@Setter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class WorkoutFeedbackLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "record_id", nullable = false)
    private WorkoutRecord workoutRecord;

    @Column(nullable = false, length = 255)
    private String feedbackNote;
}
