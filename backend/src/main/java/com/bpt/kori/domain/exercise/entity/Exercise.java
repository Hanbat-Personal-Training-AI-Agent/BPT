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

    @Column(length = 50)
    private String targetMuscle;

    @Column(precision = 5, scale = 2)
    private BigDecimal standardRomMin;

    @Column(precision = 5, scale = 2)
    private BigDecimal standardRomMax;

    @Column(length = 255)
    private String cameraGuideNote;

    @Column(length = 500)
    private String thumbnailUrl;

    @Column(length = 500)
    private String guideVideoUrl;
}
