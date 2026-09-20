package com.bpt.kori.domain.user.repository;

import com.bpt.kori.domain.user.entity.UserCalibration;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface UserCalibrationRepository extends JpaRepository<UserCalibration, Long> {

    Optional<UserCalibration> findTopByUserIdOrderByCalibratedAtDesc(Long userId);

    Optional<UserCalibration> findByJobId(String jobId);
}
