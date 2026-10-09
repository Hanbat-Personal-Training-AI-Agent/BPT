package com.bpt.kori.domain.workout.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "workout_set_records")
@Getter
@Setter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class WorkoutSetRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "workout_record_id", nullable = false)
    private WorkoutRecord workoutRecord;

    @Column(nullable = false)
    private Integer setNumber;

    @Column(nullable = false)
    private Integer reps;

    private Double weightKg;

    @Column(length = 50)
    private String postureStatus; // "안정", "주의", "위험"
}
