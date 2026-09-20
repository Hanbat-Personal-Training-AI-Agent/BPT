package com.bpt.kori.domain.user.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "user_calibrations")
@Getter
@Setter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class UserCalibration {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(columnDefinition = "TEXT")
    private String smplBeta;

    @Column(columnDefinition = "TEXT")
    private String boneLengthData;

    @Column(length = 64, nullable = false)
    private String jobId;

    @Column(length = 20)
    @Builder.Default
    private String status = "COMPLETED";

    private Integer progressRate;

    @Column(length = 500)
    private String modelGlbUrl;

    @Column(length = 255)
    private String coachComment;

    private LocalDateTime calibratedAt;
}
