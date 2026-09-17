import 'package:flutter/material.dart' show Color;

enum ExerciseType { reps, duration }

enum DifficultyLevel { beginner, intermediate, advanced }

class ExerciseModel {
  final String id;
  final String name;
  final String nameKr;
  final String description;
  final String imagePath;
  final ExerciseType type;
  final int defaultReps;
  final int defaultSets;
  final int defaultDurationSeconds;
  final List<String> targetMuscles;
  final DifficultyLevel difficulty;
  final Color accentColor;
  final bool usesWeight;

  const ExerciseModel({
    required this.id,
    required this.name,
    required this.nameKr,
    required this.description,
    required this.imagePath,
    required this.type,
    required this.defaultReps,
    required this.defaultSets,
    required this.defaultDurationSeconds,
    required this.targetMuscles,
    required this.difficulty,
    required this.accentColor,
    this.usesWeight = true,
  });

  String get difficultyLabel {
    switch (difficulty) {
      case DifficultyLevel.beginner:
        return 'Beginner';
      case DifficultyLevel.intermediate:
        return 'Intermediate';
      case DifficultyLevel.advanced:
        return 'Advanced';
    }
  }
}
