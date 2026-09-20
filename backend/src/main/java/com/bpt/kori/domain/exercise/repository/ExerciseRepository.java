package com.bpt.kori.domain.exercise.repository;

import com.bpt.kori.domain.exercise.entity.Exercise;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface ExerciseRepository extends JpaRepository<Exercise, Long> {

    Optional<Exercise> findByExerciseCode(String exerciseCode);

    List<Exercise> findAllByCategory(String category);
}
