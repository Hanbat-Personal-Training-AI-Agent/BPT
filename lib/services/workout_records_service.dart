import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dto/workout_metadata_dto.dart';
import '../data/repositories/workout_repository.dart';
import '../models/workout_record_model.dart';

/// Riverpod StateNotifier managing Workout Record history using AsyncValue
class WorkoutRecordsNotifier
    extends StateNotifier<AsyncValue<List<WorkoutRecordModel>>> {
  final IWorkoutRepository _repository;

  WorkoutRecordsNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadRecords();
  }

  /// Fetch records from Repository (Spring Boot API + Local Cache fallback)
  Future<void> loadRecords() async {
    state = const AsyncValue.loading();
    try {
      final records = await _repository.getWorkoutRecords();
      if (!mounted) return;
      state = AsyncValue.data(
          [...records]..sort((a, b) => b.date.compareTo(a.date)));
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  /// Submits On-Device AI metadata (Lightweight JSON with postureScore)
  /// Updates Riverpod AsyncValue state safely after API / Offline completion.
  Future<WorkoutRecordModel?> addMetadataRecord(
    WorkoutMetadataRequestDto dto,
  ) async {
    try {
      final newRecord = await _repository.submitWorkoutRecord(dto);
      if (!mounted) return null;

      final currentRecords = state.value ?? [];
      final updatedList = [
        newRecord,
        ...currentRecords.where((r) => r.id != newRecord.id),
      ]..sort((a, b) => b.date.compareTo(a.date));

      state = AsyncValue.data(updatedList);
      return newRecord;
    } catch (e, st) {
      if (!mounted) return null;
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Returns active streak days based on current records
  int get streakDays {
    final list = state.value ?? [];
    if (list.isEmpty) return 0;

    final today = _dateOnly(DateTime.now());
    final uniqueDays = list.map((r) => _dateOnly(r.date)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    final diff = today.difference(uniqueDays.first).inDays;
    if (diff > 1) return 0;

    int streak = 1;
    for (int i = 1; i < uniqueDays.length; i++) {
      final expected = uniqueDays[i - 1].subtract(const Duration(days: 1));
      if (uniqueDays[i] == expected) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
}

final workoutRecordsProvider = StateNotifierProvider<WorkoutRecordsNotifier,
    AsyncValue<List<WorkoutRecordModel>>>(
  (ref) {
    final repository = ref.watch(workoutRepositoryProvider);
    return WorkoutRecordsNotifier(repository);
  },
);
