package com.bpt.kori.domain.exercise.service;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.exercise.entity.Exercise;
import com.bpt.kori.domain.exercise.repository.ExerciseRepository;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ExerciseService {

    private final ExerciseRepository exerciseRepository;

    @PostConstruct
    @Transactional
    public void initExercises() {
        if (exerciseRepository.count() == 0) {
            exerciseRepository.save(Exercise.builder()
                    .exerciseCode("SQUAT")
                    .exerciseName("바벨 백 스쿼트")
                    .category("LEGS")
                    .standardRomMin(BigDecimal.valueOf(80.0))
                    .standardRomMax(BigDecimal.valueOf(110.0))
                    .build());

            exerciseRepository.save(Exercise.builder()
                    .exerciseCode("BENCH_PRESS")
                    .exerciseName("바벨 벤치프레스")
                    .category("CHEST")
                    .standardRomMin(BigDecimal.valueOf(75.0))
                    .standardRomMax(BigDecimal.valueOf(95.0))
                    .build());

            exerciseRepository.save(Exercise.builder()
                    .exerciseCode("DEADLIFT")
                    .exerciseName("컨벤셔널 데드리프트")
                    .category("BACK")
                    .standardRomMin(BigDecimal.valueOf(60.0))
                    .standardRomMax(BigDecimal.valueOf(100.0))
                    .build());
        }
    }

    public List<Exercise> getAllExercises(String category) {
        if (category != null && !category.isBlank()) {
            return exerciseRepository.findAllByCategory(category.toUpperCase());
        }
        return exerciseRepository.findAll();
    }

    public Exercise getExerciseById(Long id) {
        return exerciseRepository.findById(id)
                .orElseThrow(() -> new CustomException(ErrorCode.EXERCISE_NOT_FOUND));
    }
}
