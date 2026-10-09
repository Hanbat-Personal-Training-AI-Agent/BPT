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
        upsertExercise("PUSH_UP", "푸쉬업", "CHEST", BigDecimal.valueOf(70.0), BigDecimal.valueOf(90.0));
        upsertExercise("SQUAT", "스쿼트", "LEGS", BigDecimal.valueOf(80.0), BigDecimal.valueOf(110.0));
        upsertExercise("BARBELL_ROW", "바벨로우", "BACK", BigDecimal.valueOf(60.0), BigDecimal.valueOf(100.0));
        upsertExercise("BENCH_PRESS", "벤치프레스", "CHEST", BigDecimal.valueOf(75.0), BigDecimal.valueOf(95.0));
        upsertExercise("DEADLIFT", "데드리프트", "BACK", BigDecimal.valueOf(60.0), BigDecimal.valueOf(100.0));
    }

    private void upsertExercise(String code, String name, String category, BigDecimal romMin, BigDecimal romMax) {
        Exercise ex = exerciseRepository.findByExerciseCode(code)
                .orElse(Exercise.builder().exerciseCode(code).build());
        ex.setExerciseName(name);
        ex.setCategory(category);
        ex.setStandardRomMin(romMin);
        ex.setStandardRomMax(romMax);
        exerciseRepository.save(ex);
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
