package com.bpt.kori.domain.exercise.controller;

import com.bpt.kori.domain.exercise.entity.Exercise;
import com.bpt.kori.domain.exercise.service.ExerciseService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Tag(name = "Exercises", description = "운동 종목 마스터 정보 조회 API")
@RestController
@RequestMapping("/exercises")
@RequiredArgsConstructor
public class ExerciseController {

    private final ExerciseService exerciseService;

    @Operation(summary = "운동 종목 목록 조회", description = "전체 운동 종목 또는 카테고리별(LEGS, CHEST, BACK 등) 종목 목록을 조회합니다.")
    @GetMapping
    public ResponseEntity<List<Exercise>> getExercises(@RequestParam(value = "category", required = false) String category) {
        List<Exercise> exercises = exerciseService.getAllExercises(category);
        return ResponseEntity.ok(exercises);
    }

    @Operation(summary = "운동 종목 가이드 상세 조회", description = "특정 운동 종목의 가이드 노트, ROM 범위, 썸네일 등을 조회합니다.")
    @GetMapping("/{id}/guide")
    public ResponseEntity<Exercise> getExerciseGuide(@PathVariable("id") Long id) {
        Exercise exercise = exerciseService.getExerciseById(id);
        return ResponseEntity.ok(exercise);
    }
}
