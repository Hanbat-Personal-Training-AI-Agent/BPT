import 'package:flutter/material.dart';
import '../../../models/workout_record_model.dart';

/// Shared history presenter: performed totals and known actual sets, never goals as equal completed sets.
class WorkoutRecordCompletionText extends StatelessWidget {
  const WorkoutRecordCompletionText(
      {super.key,
      required this.record,
      required this.isKo,
      this.includeWeight = false,
      this.style});
  final WorkoutRecordModel record;
  final bool isKo;
  final bool includeWeight;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final sets = record.completedSets;
    final total =
        isKo ? '총 ${record.totalReps}회' : '${record.totalReps} reps total';
    final label = sets != null
        ? (isKo ? '$sets세트 · $total' : '$sets sets · $total')
        : record.targetSets > 0
            ? (isKo
                ? '$total · 목표 ${record.targetSets}세트'
                : '$total · goal ${record.targetSets} sets')
            : total;
    final weight = record.weightKg;
    final weightPart = includeWeight && weight > 0
        ? ' · ${weight == weight.roundToDouble() ? weight.toInt() : weight}kg'
        : '';
    return Text('$label$weightPart', style: style);
  }
}
