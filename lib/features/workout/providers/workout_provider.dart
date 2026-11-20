import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/mock_data.dart';

enum WorkoutStatus { idle, countdown, active, paused, setComplete, complete }

class WorkoutState {
  final WorkoutStatus status;
  final String exerciseId;
  final int targetReps;
  final int targetSets;
  final int currentSet;
  final int currentReps;
  final int correctReps;
  final int incorrectReps;
  final int elapsedSeconds;
  final int countdownValue;
  final String feedbackMessage;
  final List<String> feedbackHistory;
  final double? postureScore;
  final bool isPoseDetected;
  final int accumulatedReps;
  final int accumulatedCorrect;
  final int accumulatedIncorrect;

  const WorkoutState({
    this.status = WorkoutStatus.idle,
    this.exerciseId = 'squat',
    this.targetReps = 15,
    this.targetSets = 3,
    this.currentSet = 1,
    this.currentReps = 0,
    this.correctReps = 0,
    this.incorrectReps = 0,
    this.elapsedSeconds = 0,
    this.countdownValue = 3,
    this.feedbackMessage = 'Position yourself in front of the camera',
    this.feedbackHistory = const [],
    this.postureScore,
    this.isPoseDetected = false,
    this.accumulatedReps = 0,
    this.accumulatedCorrect = 0,
    this.accumulatedIncorrect = 0,
  });

  WorkoutState copyWith({
    WorkoutStatus? status,
    String? exerciseId,
    int? targetReps,
    int? targetSets,
    int? currentSet,
    int? currentReps,
    int? correctReps,
    int? incorrectReps,
    int? elapsedSeconds,
    int? countdownValue,
    String? feedbackMessage,
    List<String>? feedbackHistory,
    double? postureScore,
    bool? isPoseDetected,
    int? accumulatedReps,
    int? accumulatedCorrect,
    int? accumulatedIncorrect,
  }) {
    return WorkoutState(
      status: status ?? this.status,
      exerciseId: exerciseId ?? this.exerciseId,
      targetReps: targetReps ?? this.targetReps,
      targetSets: targetSets ?? this.targetSets,
      currentSet: currentSet ?? this.currentSet,
      currentReps: currentReps ?? this.currentReps,
      correctReps: correctReps ?? this.correctReps,
      incorrectReps: incorrectReps ?? this.incorrectReps,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      countdownValue: countdownValue ?? this.countdownValue,
      feedbackMessage: feedbackMessage ?? this.feedbackMessage,
      feedbackHistory: feedbackHistory ?? this.feedbackHistory,
      postureScore: postureScore ?? this.postureScore,
      isPoseDetected: isPoseDetected ?? this.isPoseDetected,
      accumulatedReps: accumulatedReps ?? this.accumulatedReps,
      accumulatedCorrect: accumulatedCorrect ?? this.accumulatedCorrect,
      accumulatedIncorrect: accumulatedIncorrect ?? this.accumulatedIncorrect,
    );
  }

  double get progress =>
      targetReps == 0 ? 0 : (currentReps / targetReps).clamp(0.0, 1.0);

  String get elapsedFormatted {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Legacy demo simulator; not the native workout route and never form evidence.
class WorkoutNotifier extends StateNotifier<WorkoutState> {
  WorkoutNotifier() : super(const WorkoutState());

  Timer? _mainTimer;
  Timer? _feedbackTimer;
  Timer? _countdownTimer;
  Timer? _repTimer;
  final _rng = Random();
  int _feedbackIndex = 0;

  void initialize(String exerciseId, int targetReps, int targetSets) {
    state = WorkoutState(
      exerciseId: exerciseId,
      targetReps: targetReps,
      targetSets: targetSets,
      feedbackMessage: 'Position yourself in frame',
    );
  }

  void startCountdown() {
    state = state.copyWith(
      status: WorkoutStatus.countdown,
      countdownValue: 3,
    );

    int count = 3;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      count--;
      if (count <= 0) {
        t.cancel();
        _startActive();
      } else {
        state = state.copyWith(countdownValue: count);
      }
    });
  }

  void _startActive() {
    state = state.copyWith(
      status: WorkoutStatus.active,
      isPoseDetected: true,
      feedbackMessage: 'Great! Starting now...',
    );
    _startTimers();
  }

  void _startTimers() {
    // Elapsed time
    _mainTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });

    // Simulated rep detection every 2-3 seconds
    _scheduleNextRep();

    // Feedback rotation every 3 seconds
    _feedbackTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _feedbackIndex = (_feedbackIndex + 1) % workoutFeedbacks.length;
      state = state.copyWith(
        feedbackMessage: workoutFeedbacks[_feedbackIndex],
        postureScore: null,
      );
    });
  }

  void _scheduleNextRep() {
    final delay = Duration(milliseconds: 1800 + _rng.nextInt(1200));
    _repTimer = Timer(delay, () {
      if (state.status != WorkoutStatus.active) return;
      _addRep();
      if (state.status == WorkoutStatus.active) {
        _scheduleNextRep();
      }
    });
  }

  void _addRep() {
    final isCorrect = _rng.nextDouble() > 0.2;
    final newReps = state.currentReps + 1;
    final newCorrect = state.correctReps + (isCorrect ? 1 : 0);
    final newIncorrect = state.incorrectReps + (isCorrect ? 0 : 1);

    final history = List<String>.from(state.feedbackHistory);
    if (!isCorrect) {
      history.insert(0, 'Rep $newReps: Check your form');
    }

    if (newReps >= state.targetReps) {
      _stopAllTimers();
      final newAccReps = state.accumulatedReps + newReps;
      final newAccCorrect = state.accumulatedCorrect + newCorrect;
      final newAccIncorrect = state.accumulatedIncorrect + newIncorrect;

      if (state.currentSet < state.targetSets) {
        // 더 남은 세트 있음 → setComplete 상태로 전환
        state = state.copyWith(
          currentReps: newReps,
          correctReps: newCorrect,
          incorrectReps: newIncorrect,
          accumulatedReps: newAccReps,
          accumulatedCorrect: newAccCorrect,
          accumulatedIncorrect: newAccIncorrect,
          feedbackHistory: history,
          status: WorkoutStatus.setComplete,
          feedbackMessage: 'Set ${state.currentSet} complete!',
          postureScore: null,
        );
      } else {
        // 모든 세트 완료
        state = state.copyWith(
          currentReps: newReps,
          correctReps: newCorrect,
          incorrectReps: newIncorrect,
          accumulatedReps: newAccReps,
          accumulatedCorrect: newAccCorrect,
          accumulatedIncorrect: newAccIncorrect,
          feedbackHistory: history,
          status: WorkoutStatus.complete,
          feedbackMessage: 'Workout complete! Great job!',
          postureScore: null,
        );
      }
    } else {
      state = state.copyWith(
        currentReps: newReps,
        correctReps: newCorrect,
        incorrectReps: newIncorrect,
        feedbackHistory: history,
        feedbackMessage: 'Demo rep counted — form not assessed',
        postureScore: null,
      );
    }
  }

  void startNextSet() {
    final nextSet = state.currentSet + 1;
    state = state.copyWith(
      status: WorkoutStatus.countdown,
      currentSet: nextSet,
      currentReps: 0,
      correctReps: 0,
      incorrectReps: 0,
      countdownValue: 3,
      isPoseDetected: false,
      feedbackMessage: 'Get ready for set $nextSet!',
    );

    int count = 3;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      count--;
      if (count <= 0) {
        t.cancel();
        _startActive();
      } else {
        state = state.copyWith(countdownValue: count);
      }
    });
  }

  void pauseWorkout() {
    _stopAllTimers();
    state = state.copyWith(
      status: WorkoutStatus.paused,
      feedbackMessage: 'Paused',
    );
  }

  void resumeWorkout() {
    state = state.copyWith(
      status: WorkoutStatus.active,
      feedbackMessage: 'Resuming...',
    );
    _startTimers();
  }

  void stopWorkout() {
    _stopAllTimers();
    state = state.copyWith(
      status: WorkoutStatus.complete,
      feedbackMessage: 'Workout stopped',
    );
  }

  void reset() {
    _stopAllTimers();
    state = const WorkoutState();
  }

  void _stopAllTimers() {
    _mainTimer?.cancel();
    _feedbackTimer?.cancel();
    _countdownTimer?.cancel();
    _repTimer?.cancel();
  }

  @override
  void dispose() {
    _stopAllTimers();
    super.dispose();
  }
}

final workoutProvider =
    StateNotifierProvider<WorkoutNotifier, WorkoutState>(
  (ref) => WorkoutNotifier(),
);
