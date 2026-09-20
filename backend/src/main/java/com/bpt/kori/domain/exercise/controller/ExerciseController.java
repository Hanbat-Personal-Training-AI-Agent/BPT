package com.bpt.kori.domain.exercise.controller;

import com.bpt.kori.domain.exercise.entity.Exercise;
import com.bpt.kori.domain.exercise.service.ExerciseService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/exercises")
@RequiredArgsConstructor
public class ExerciseController {

    private final ExerciseService exerciseService;

    @GetMapping
    public ResponseEntity<List<Exercise>> getExercises(@RequestParam(value = "category", required = false) String category) {
        List<Exercise> exercises = exerciseService.getAllExercises(category);
        return ResponseEntity.ok(exercises);
    }

    @GetMapping("/{id}/guide")
    public ResponseEntity<Exercise> getExerciseGuide(@PathVariable("id") Long id) {
        Exercise exercise = exerciseService.getExerciseById(id);
        return ResponseEntity.ok(exercise);
    }
}
