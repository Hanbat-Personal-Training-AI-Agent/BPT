package com.bpt.kori.domain.exercise.entity;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;

@Entity
@Table(name = "exercises")
@Getter
@Setter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class Exercise {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 30)
    private String exerciseCode;

    @Column(nullable = false, length = 50)
    private String exerciseName;

    @Column(length = 30)
    private String category;

    @Column(precision = 5, scale = 2)
    private BigDecimal standardRomMin;

    @Column(precision = 5, scale = 2)
    private BigDecimal standardRomMax;

    @Column(length = 30)
    private String appExerciseId;

    public String getAppExerciseId() {
        if (this.appExerciseId != null && !this.appExerciseId.isBlank()) {
            return this.appExerciseId;
        }
        if (this.exerciseCode != null) {
            return switch (this.exerciseCode.toUpperCase()) {
                case "SQUAT" -> "squat";
                case "BENCH_PRESS" -> "benchpress";
                case "BARBELL_ROW" -> "barbell-row";
                case "PUSH_UP" -> "pushup";
                case "DEADLIFT" -> "deadlift";
                default -> this.exerciseCode.toLowerCase().replace("_", "-");
            };
        }
        return null;
    }
}
