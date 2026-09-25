package com.bpt.kori.domain.user.entity;

import jakarta.persistence.*;
import lombok.*;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "users")
@Getter
@Setter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
@EntityListeners(AuditingEntityListener.class)
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 100)
    private String email;

    @Column(nullable = false, length = 255)
    private String password;

    @Column(nullable = false, unique = true, length = 50)
    private String username;

    @Column(length = 50)
    private String name;

    @Column(length = 20)
    private String phoneNumber;

    @Column(length = 20)
    private String gender; // MALE, FEMALE, NOT_SPECIFIED

    private LocalDate birthDate;

    @Column(precision = 5, scale = 2)
    @Builder.Default
    private BigDecimal heightCm = BigDecimal.ZERO;

    @Column(precision = 5, scale = 2)
    @Builder.Default
    private BigDecimal weightKg = BigDecimal.ZERO;

    @Column(length = 50)
    private String workoutGoal;

    @Builder.Default
    private Integer weeklyFrequency = 3;

    @Builder.Default
    private Integer totalWorkouts = 0;

    @Builder.Default
    private Integer streakDays = 0;

    @Builder.Default
    private Boolean isOnboardingCompleted = false;

    @Builder.Default
    @Column(nullable = false)
    private Boolean termsAgreed = false;

    @Builder.Default
    @Column(nullable = false)
    private Boolean privacyAgreed = false;

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @LastModifiedDate
    @Column(nullable = false)
    private LocalDateTime updatedAt;

    public void updateOnboarding(String gender, BigDecimal heightCm, BigDecimal weightKg, String workoutGoal, Integer weeklyFrequency) {
        if (gender != null) this.gender = gender;
        if (heightCm != null) this.heightCm = heightCm;
        if (weightKg != null) this.weightKg = weightKg;
        if (workoutGoal != null) this.workoutGoal = workoutGoal;
        if (weeklyFrequency != null) this.weeklyFrequency = weeklyFrequency;
        this.isOnboardingCompleted = true;
    }

    public void incrementWorkoutCount() {
        this.totalWorkouts = (this.totalWorkouts == null ? 0 : this.totalWorkouts) + 1;
    }
}
