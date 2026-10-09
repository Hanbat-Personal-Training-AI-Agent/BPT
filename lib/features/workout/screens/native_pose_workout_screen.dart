import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/mock_data.dart';
import '../../home/providers/home_provider.dart';
import '../data/kori_feedback_lines.dart';

/// Preparation phases shown before the native camera PlatformView appears.
enum _PrepPhase { alignHint, countdown, live }

class NativePoseWorkoutScreen extends ConsumerStatefulWidget {
  const NativePoseWorkoutScreen({
    super.key,
    required this.exerciseId,
    this.targetReps = 15,
    this.targetSets = 3,
    this.setWeightsKg = const [],
    this.setReps = const [],
    this.restSeconds = _defaultRestSeconds,
  });

  static const int _defaultRestSeconds = 60;

  static const String viewType = 'bpt/native_pose_camera';
  static const Set<String> supportedExerciseIds = {
    'deadlift',
    'benchpress',
    'squat',
    'barbell-row',
    'pushup',
  };

  final String exerciseId;
  final int targetReps;
  final int targetSets;

  /// 운동 시작 화면에서 정한 세트별 무게. 비어 있으면 운동별 기본 무게를 쓴다.
  final List<int> setWeightsKg;

  /// 세트별 목표 반복 수. 비어 있으면 모든 세트가 [targetReps].
  final List<int> setReps;

  /// 세트 사이 쉬는 시간(초).
  final int restSeconds;

  @override
  ConsumerState<NativePoseWorkoutScreen> createState() =>
      _NativePoseWorkoutScreenState();
}

class _NativePoseWorkoutScreenState
    extends ConsumerState<NativePoseWorkoutScreen> {
  // "카메라를 몸 전체가 보이도록 맞춰주세요" guidance duration before the countdown.
  static const Duration _alignHintDuration = Duration(milliseconds: 1800);

  Timer? _alignTimer;
  Timer? _countdownTimer;
  Timer? _elapsedTimer;
  Timer? _restTimer;
  MethodChannel? _channel;

  _PrepPhase _phase = _PrepPhase.alignHint;
  int _count = 3;

  // Rep/set tracking, driven by the native evaluator updates over the channel.
  int _currentSet = 1;
  int _setStartRep = 0; // native cumulative rep at the start of the current set
  int _latestNativeRep = 0; // most recent native cumulative rep
  bool _setComplete = false;
  bool _workoutComplete = false;
  DateTime? _liveStartedAt;

  // 상단 경과 시간 + "잠깐 쉬기" 일시정지 상태.
  int _elapsedSeconds = 0;
  bool _isPaused = false;

  // 코리 피드백: 네이티브가 `onFeedback` 으로 보낸 대사 키를 보여준다
  // (kori_feedback_lines.dart). `silent: true` 인 키는 말풍선 없이 세트 요약에만 넣는다.
  // 첫 피드백 전에는 운동별 기본 팁을 보여준다.
  String? _feedbackKey;
  int? _feedbackCount;
  int _badCountThisSet = 0;
  final Set<String> _warningKeysThisSet = {};

  // 브레이크 타임: 세트 사이 휴식 타이머 + 세트별 기록.
  late int _restTotal = widget.restSeconds;
  late int _restRemaining = widget.restSeconds;
  final List<_SetResult> _setResults = [];

  /// [setNumber] 번째 세트(1부터)에 들 무게.
  int _weightForSetNumber(int setNumber) {
    final weights = widget.setWeightsKg;
    if (setNumber >= 1 && setNumber <= weights.length) {
      return weights[setNumber - 1];
    }
    return ref.read(defaultWeightKgProvider(widget.exerciseId));
  }

  int get _weightForSet => _weightForSetNumber(_currentSet);

  List<int> get _plannedWeights =>
      List.generate(widget.targetSets, (i) => _weightForSetNumber(i + 1));

  /// [setNumber] 번째 세트(1부터)의 목표 반복 수.
  int _repsForSetNumber(int setNumber) {
    final reps = widget.setReps;
    if (setNumber >= 1 && setNumber <= reps.length) return reps[setNumber - 1];
    return widget.targetReps;
  }

  int get _targetRepsThisSet => _repsForSetNumber(_currentSet);

  List<int> get _plannedReps =>
      List.generate(widget.targetSets, (i) => _repsForSetNumber(i + 1));

  int get _totalPlannedReps => _plannedReps.fold(0, (sum, r) => sum + r);

  bool get _isSupportedExercise =>
      NativePoseWorkoutScreen.supportedExerciseIds.contains(widget.exerciseId);
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  int get _repsThisSet {
    final v = _latestNativeRep - _setStartRep;
    if (v < 0) return 0;
    if (v > _targetRepsThisSet) return _targetRepsThisSet;
    return v;
  }

  @override
  void initState() {
    super.initState();
    _alignTimer = Timer(_alignHintDuration, _startCountdown);
  }

  void _startCountdown() {
    if (!mounted) return;
    setState(() {
      _phase = _PrepPhase.countdown;
      _count = 3;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_count <= 1) {
        timer.cancel();
        setState(() {
          _phase = _PrepPhase.live;
          _liveStartedAt = DateTime.now();
        });
        _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          if (!_isPaused) setState(() => _elapsedSeconds += 1);
        });
      } else {
        setState(() => _count -= 1);
      }
    });
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('${NativePoseWorkoutScreen.viewType}/$id');
    _channel!.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onPoseUpdate') {
      final args = (call.arguments as Map).cast<String, dynamic>();
      final rep = (args['rep'] as num?)?.toInt() ?? _latestNativeRep;
      _onNativeUpdate(rep);
    } else if (call.method == 'onFeedback') {
      // { key: 'squat_shallow', n?: 3, silent?: true } — key는 kori_feedback_lines.dart 목록 기준.
      final args = (call.arguments as Map).cast<String, dynamic>();
      final key = args['key'] as String?;
      if (key != null) {
        _onNativeFeedback(
          key,
          (args['n'] as num?)?.toInt(),
          silent: args['silent'] == true,
        );
      }
    }
    return null;
  }

  void _onNativeFeedback(String key, int? count, {bool silent = false}) {
    final line = koriFeedbackLines[key];
    if (!mounted || _isPaused || line == null) return;
    if (_setComplete || _workoutComplete) return;
    if (silent) {
      // 참고 등급 등: 말하지 않고 세트 후 요약(고칠 점 개수)에만 반영.
      if (line.kind == KoriFeedbackKind.warning) _warningKeysThisSet.add(key);
      return;
    }
    setState(() {
      _feedbackKey = key;
      _feedbackCount = count;
      if (line.kind == KoriFeedbackKind.warning) {
        _badCountThisSet += 1;
        _warningKeysThisSet.add(key);
      }
    });
  }

  // TODO(temp): 시뮬레이터에서는 카메라가 없어 반복 수가 안 들어오므로,
  // 네이티브 카메라가 보내는 반복 수 이벤트를 대신 흉내 내는 테스트용 동작.
  void _debugAddRep() => _onNativeUpdate(_latestNativeRep + 1);

  void _debugFinishSet() => _onNativeUpdate(_setStartRep + _targetRepsThisSet);

  void _onNativeUpdate(int rep) {
    if (!mounted || _isPaused) return;
    setState(() {
      _latestNativeRep = rep;
      // Don't advance set state while a set-complete / done prompt is showing;
      // reps performed during the rest period are discarded on "next set".
      if (_setComplete || _workoutComplete) return;
      if (rep - _setStartRep >= _targetRepsThisSet) {
        _setResults.add(
          _SetResult(
            reps: _targetRepsThisSet,
            weightKg: _weightForSet,
            badCount: _badCountThisSet,
            fixCount: _warningKeysThisSet.length,
          ),
        );
        if (_currentSet < widget.targetSets) {
          _setComplete = true;
          _startRestTimer();
        } else {
          _workoutComplete = true;
        }
      }
    });
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
  }

  void _startRestTimer() {
    _restTimer?.cancel();
    _restTotal = widget.restSeconds;
    _restRemaining = widget.restSeconds;
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_restRemaining <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _restRemaining -= 1);
    });
  }

  void _adjustRest(int deltaSeconds) {
    setState(() {
      _restTotal = (_restTotal + deltaSeconds)
          .clamp(15, math.max(300, widget.restSeconds));
      _restRemaining = (_restRemaining + deltaSeconds).clamp(0, _restTotal);
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    _startNextSet();
  }

  void _startNextSet() {
    _restTimer?.cancel();
    setState(() {
      _currentSet += 1;
      _setStartRep = _latestNativeRep; // snapshot: discard rest-period reps
      _setComplete = false;
      _badCountThisSet = 0;
      _warningKeysThisSet.clear();
      _feedbackKey = null;
      _feedbackCount = null;
    });
  }

  /// "끝내기"를 실수로 눌렀을 수 있으니 한 번 더 확인한다. 모달이 떠 있는 동안은
  /// 일시정지해서 반복 수가 세지지 않게 하고, 닫으면 원래 상태로 돌려놓는다.
  Future<void> _confirmEnd() async {
    final wasPaused = _isPaused;
    if (!wasPaused) setState(() => _isPaused = true);

    final doneReps =
        _setResults.fold<int>(0, (sum, r) => sum + r.reps) + _repsThisSet;
    final isKo = ref.read(appStringsProvider).locale == 'ko';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => _EndConfirmDialog(isKo: isKo, doneReps: doneReps),
    );
    if (!mounted) return;

    if (confirmed == true) {
      _finishWorkout();
    } else if (!wasPaused) {
      setState(() => _isPaused = false);
    }
  }

  void _finishWorkout() {
    if (!mounted) return;

    // 실제로 수행한 세트만 모은다. 끝난 세트 + 진행 중이던 세트(1회 이상 했을 때).
    // 쉬는 시간/완료 화면에서는 방금 끝낸 세트가 이미 _setResults 에 들어 있다.
    final performedSets = [
      ..._setResults,
      if (!_setComplete && !_workoutComplete && _repsThisSet > 0)
        _SetResult(
          reps: _repsThisSet,
          weightKg: _weightForSet,
          badCount: _badCountThisSet,
          fixCount: _warningKeysThisSet.length,
        ),
    ];
    final totalReps = performedSets.fold<int>(0, (sum, r) => sum + r.reps);

    // 한 회도 안 하고 끝내면 기록을 남기지 않고 운동 선택 화면으로 돌아간다.
    if (totalReps == 0) {
      final isKo = ref.read(appStringsProvider).locale == 'ko';
      showAppToast(
        context,
        isKo
            ? '수행한 횟수가 없어서 기록을 저장하지 않았어.'
            : 'No reps completed, so nothing was saved.',
      );
      context.go(RouteConstants.exerciseSelection);
      return;
    }

    final exercise = findExercise(widget.exerciseId);
    final elapsedSeconds = _liveStartedAt == null
        ? 0
        : DateTime.now().difference(_liveStartedAt!).inSeconds;

    final totalBad = performedSets.fold<int>(0, (sum, r) => sum + r.badCount);

    context.pushReplacement(
      RouteConstants.workoutResult,
      extra: {
        'exerciseId': widget.exerciseId,
        'exerciseName': exercise.name,
        'exerciseNameKr': exercise.nameKr,
        'totalReps': totalReps,
        'correctReps': totalReps - totalBad,
        'incorrectReps': totalBad,
        'elapsedSeconds': elapsedSeconds,
        'postureScore': null,
        'feedbackHistory': null,
        'targetReps': _totalPlannedReps,
        // 계획한 세트 수가 아니라 실제로 수행한 세트 수를 기록한다.
        'targetSets': performedSets.length,
        'setResults': performedSets
            .map((r) => {
                  'reps': r.reps,
                  'weightKg': r.weightKg,
                  'badCount': r.badCount,
                })
            .toList(),
      },
    );
  }

  @override
  void dispose() {
    _alignTimer?.cancel();
    _countdownTimer?.cancel();
    _elapsedTimer?.cancel();
    _restTimer?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final isKo = s.locale == 'ko';
    final exercise = findExercise(widget.exerciseId);
    final exName = isKo ? exercise.nameKr : exercise.name;

    // 실시간 트래킹 중에는 뒤로가기 대신 "끝내기" 버튼으로만 나가도록 숨긴다.
    final isLiveTracking =
        _phase == _PrepPhase.live && !_setComplete && !_workoutComplete;

    // 운동 완료 화면에서는 뒤로가기(버튼·스와이프)를 막고 "결과 보러 가기"로만 나간다.
    return PopScope(
      canPop: !_workoutComplete,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: _buildBody(context, exName, isKo)),
            if (!isLiveTracking && !_setComplete && !_workoutComplete)
              Positioned.fill(
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String exerciseName,
    bool isKo,
  ) {
    // Don't create the native UiKitView until the countdown has completed.
    if (_phase != _PrepPhase.live) {
      return _PrepOverlay(
        phase: _phase,
        count: _count,
        exerciseName: exerciseName,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 네이티브 카메라는 iOS + 지원 운동에서만 띄운다. 그 외에는 검은 배경으로
        // 두고 나머지 운동 흐름(HUD·휴식·완료)은 그대로 진행한다.
        if (_isSupportedExercise && _isIOS)
          UiKitView(
            viewType: NativePoseWorkoutScreen.viewType,
            creationParams: {'exerciseId': widget.exerciseId},
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onPlatformViewCreated,
          )
        else
          const ColoredBox(color: Colors.black),
        if (!_setComplete && !_workoutComplete)
          Positioned.fill(
            child: SafeArea(
              child: _LiveHud(
                isKo: isKo,
                exerciseId: widget.exerciseId,
                exerciseName: exerciseName,
                elapsedSeconds: _elapsedSeconds,
                reps: _repsThisSet,
                targetReps: _targetRepsThisSet,
                currentSet: _currentSet,
                totalSets: widget.targetSets,
                feedbackKey: _feedbackKey,
                feedbackCount: _feedbackCount,
                isPaused: _isPaused,
                onTogglePause: _togglePause,
                onEnd: _confirmEnd,
              ),
            ),
          ),
        // TODO(temp): 디버그 빌드에서만 보이는 테스트 버튼. 실제 기기 카메라
        // 연동 검증이 끝나면 제거할 것.
        if (kDebugMode && !_setComplete && !_workoutComplete)
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _DebugButton(label: '+1회 (테스트용)', onTap: _debugAddRep),
                  const SizedBox(height: 10),
                  _DebugButton(label: '세트 채우기 (테스트용)', onTap: _debugFinishSet),
                ],
              ),
            ),
          ),
        if (_setComplete)
          Positioned.fill(
            child: _BreakTimeOverlay(
              isKo: isKo,
              exerciseName: exerciseName,
              completedSet: _currentSet,
              totalSets: widget.targetSets,
              restRemaining: _restRemaining,
              restTotal: _restTotal,
              setResults: _setResults,
              plannedReps: _plannedReps,
              plannedWeightsKg: _plannedWeights,
              onAdjustRest: _adjustRest,
              onSkipRest: _skipRest,
              onNext: _startNextSet,
            ),
          ),
        if (_workoutComplete)
          _WorkoutCompleteOverlay(
            totalSets: widget.targetSets,
            isKo: isKo,
            onFinish: _finishWorkout,
          ),
      ],
    );
  }
}

class _DebugButton extends StatelessWidget {
  const _DebugButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.red, width: 1.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.red,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Full-screen preparation UI shown before the native camera appears.
class _PrepOverlay extends StatelessWidget {
  const _PrepOverlay({
    required this.phase,
    required this.count,
    required this.exerciseName,
  });

  final _PrepPhase phase;
  final int count;
  final String exerciseName;

  @override
  Widget build(BuildContext context) {
    final isCountdown = phase == _PrepPhase.countdown;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              exerciseName,
              style: const TextStyle(
                color: AppColors.green,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 28),
            if (isCountdown) ...[
              const Text(
                '자, 준비하자!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: 128,
                height: 128,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.green.withValues(alpha: 0.14),
                  border: Border.all(color: AppColors.green, width: 3),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ] else ...[
              Image.asset(
                'assets/images/character/advice.png',
                width: 110,
                height: 110,
              ),
              const SizedBox(height: 24),
              const Text(
                '몸 전체가 잘 보이게 카메라 맞춰줘!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 실시간 트래킹 화면 HUD: 상단 바(운동명·경과시간) + REPS/SET 카드 +
/// 코리 피드백 말풍선 + 세트 진행 바 + 하단 액션 버튼.
class _LiveHud extends StatelessWidget {
  const _LiveHud({
    required this.isKo,
    required this.exerciseId,
    required this.exerciseName,
    required this.elapsedSeconds,
    required this.reps,
    required this.targetReps,
    required this.currentSet,
    required this.totalSets,
    required this.feedbackKey,
    required this.feedbackCount,
    required this.isPaused,
    required this.onTogglePause,
    required this.onEnd,
  });

  final bool isKo;
  final String exerciseId;
  final String exerciseName;
  final int elapsedSeconds;
  final int reps;
  final int targetReps;
  final int currentSet;
  final int totalSets;
  /// null이면 첫 피드백 전 기본 팁.
  final String? feedbackKey;
  final int? feedbackCount;
  final bool isPaused;
  final VoidCallback onTogglePause;
  final VoidCallback onEnd;

  String get _elapsedLabel {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final sec = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.grey,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      exerciseName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _elapsedLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const _SoundToggleButton(),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatCard(
                label: 'REPS',
                value: '$reps',
                suffix: isKo ? '/ $targetReps회' : '/ $targetReps',
                filled: false,
              ),
              const Spacer(),
              _StatCard(
                label: 'SET',
                value: '$currentSet',
                suffix: isKo ? '/ $totalSets세트' : '/ $totalSets',
                filled: true,
              ),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _KoriFeedbackRow(
            isKo: isKo,
            exerciseId: exerciseId,
            feedbackKey: feedbackKey,
            feedbackCount: feedbackCount,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _SetProgressBar(currentSet: currentSet, totalSets: totalSets),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(child: _EndButton(isKo: isKo, onTap: onEnd)),
              const SizedBox(width: 8),
              Expanded(
                child: _PauseButton(
                  isKo: isKo,
                  isPaused: isPaused,
                  onTap: onTogglePause,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.suffix,
    required this.filled,
  });

  final String label;
  final String value;
  final String suffix;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.black : Colors.white;
    return Container(
      width: 68,
      height: 98,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: filled ? AppColors.green : AppColors.grey,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg.withValues(alpha: filled ? 0.6 : 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Stack(
              children: [
                // w900는 폰트가 지원하는 최대 굵기라, 안쪽을 살짝 두껍게
                // 덧그려서(faux bold) 실제로 더 두꺼워 보이게 만든다.
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 1.6
                      ..color = fg,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: fg,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Text(
            suffix,
            style: TextStyle(
              color: fg.withValues(alpha: filled ? 0.65 : 0.45),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 음소거 토글 버튼: 탭할 때마다 스피커 ↔ 음소거 아이콘으로 바뀐다.
/// (아직 실제 음성 피드백 재생 로직은 없어서 시각적 토글만 담당)
class _SoundToggleButton extends StatefulWidget {
  const _SoundToggleButton();

  @override
  State<_SoundToggleButton> createState() => _SoundToggleButtonState();
}

class _SoundToggleButtonState extends State<_SoundToggleButton> {
  bool _muted = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _muted = !_muted),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.grey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

/// 코리 피드백 말풍선. [feedbackKey] 대사를 보여주고, null이면 운동별 기본 팁.
class _KoriFeedbackRow extends StatelessWidget {
  // 첫 rep이 잡히기 전 기본 상태에서 운동별로 보여주는 한 줄 주의사항.
  static const Map<String, String> _idleTipsKo = {
    'squat': '무릎이 발끝 방향을 향하게 해줘',
    'benchpress': '가슴까지 천천히 바를 내려줘',
    'deadlift': '허리는 곧게 펴고 내려가',
    'barbell-row': '허리 고정하고 팔꿈치로 당겨줘',
    'pushup': '몸을 일자로 유지하면서 내려가',
  };
  static const Map<String, String> _idleTipsEn = {
    'squat': 'Keep your knees pointed toward your toes',
    'benchpress': 'Lower the bar slowly to your chest',
    'deadlift': 'Keep your back straight as you go down',
    'barbell-row': 'Brace your core and pull with your elbows',
    'pushup': 'Keep your body in a straight line',
  };

  const _KoriFeedbackRow({
    required this.isKo,
    required this.exerciseId,
    required this.feedbackKey,
    required this.feedbackCount,
  });
  final bool isKo;
  final String exerciseId;
  final String? feedbackKey;
  final int? feedbackCount;

  @override
  Widget build(BuildContext context) {
    final String characterAsset;
    final Color bubbleColor;
    final Color textColor;
    final String title;
    final String subtitle;

    final line = koriFeedbackLines[feedbackKey];
    if (line == null) {
      characterAsset = 'assets/images/character/considering.png';
      bubbleColor = AppColors.purple;
      textColor = AppColors.black;
      title = isKo ? '준비되면 시작해보자!' : "Start whenever you're ready!";
      subtitle = isKo
          ? (_idleTipsKo[exerciseId] ?? _idleTipsKo['squat']!)
          : (_idleTipsEn[exerciseId] ?? _idleTipsEn['squat']!);
    } else {
      switch (line.kind) {
        case KoriFeedbackKind.praise:
          characterAsset = 'assets/images/character/cheering.png';
          bubbleColor = AppColors.green;
          textColor = AppColors.black;
        case KoriFeedbackKind.warning:
          characterAsset = 'assets/images/character/worrying.png';
          bubbleColor = AppColors.pink;
          textColor = AppColors.white;
        case KoriFeedbackKind.setup:
          characterAsset = 'assets/images/character/considering.png';
          bubbleColor = AppColors.purple;
          textColor = AppColors.black;
      }
      final parts =
          splitKoriLine(line.render(isKo: isKo, n: feedbackCount));
      title = parts.title;
      subtitle = parts.subtitle;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 90 - 16,
          height: 90,
          child: OverflowBox(
            minWidth: 90,
            maxWidth: 90,
            alignment: Alignment.centerRight,
            child: Transform.translate(
              offset: const Offset(0, 10),
              child: Image.asset(
                characterAsset,
                width: 90,
                height: 90,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Transform.translate(
            offset: const Offset(0, -10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                  bottomLeft: Radius.circular(3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.75),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 세트 진행 바: 완료(+진행중) 세트만큼 라임색으로 채워진다.
class _SetProgressBar extends StatelessWidget {
  const _SetProgressBar({required this.currentSet, required this.totalSets});
  final int currentSet;
  final int totalSets;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSets, (i) {
        final filled = i < currentSet;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == totalSets - 1 ? 0 : 8),
            height: 5,
            decoration: BoxDecoration(
              color: filled
                  ? AppColors.green
                  : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.isKo,
    required this.isPaused,
    required this.onTap,
  });
  final bool isKo;
  final bool isPaused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.pink,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppColors.black,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              isPaused
                  ? (isKo ? '이어서 하기' : 'Resume')
                  : (isKo ? '잠깐 쉬기' : 'Pause'),
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndButton extends StatelessWidget {
  const _EndButton({required this.isKo, required this.onTap});
  final bool isKo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Text(
          isKo ? '끝내기' : 'End',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// "끝내기" 확인 모달. 왼쪽에 말하는 코리, 오른쪽에 안내 문구.
class _EndConfirmDialog extends StatelessWidget {
  const _EndConfirmDialog({required this.isKo, required this.doneReps});
  final bool isKo;
  final int doneReps;

  @override
  Widget build(BuildContext context) {
    final title = isKo ? '벌써 끝낼 거야?' : 'Done already?';
    // 한 회도 안 했으면 기록이 저장되지 않는다는 걸 미리 알려준다.
    final message = doneReps == 0
        ? (isKo
            ? '아직 한 회도 안 했어.\n지금 끝내면 기록이 안 남아!'
            : "You haven't done a rep yet.\nNothing will be saved.")
        : (isKo
            ? '지금까지 한 $doneReps회까지만\n기록으로 남길게!'
            : "I'll save the $doneReps reps\nyou've done so far.");

    return Dialog(
      backgroundColor: AppColors.grey,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0xFF5C5C5C)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/images/character/face2.png',
                  width: 76,
                  height: 76,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: TextStyle(
                          color: AppColors.white.withValues(alpha: 0.65),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            // 운동 화면 하단 버튼과 같은 배치: 왼쪽 끝내기, 오른쪽 계속하기.
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: isKo ? '끝내기' : 'End',
                    primary: false,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DialogButton(
                    label: isKo ? '계속하기' : 'Keep going',
                    primary: true,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary
              ? AppColors.green
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: primary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? AppColors.black : Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// 완료된 세트 1개의 기록 (반복 수 / 무게 / 나쁜 피드백 횟수).
class _SetResult {
  const _SetResult({
    required this.reps,
    required this.weightKg,
    required this.badCount,
    required this.fixCount,
  });
  final int reps;
  final int weightKg;

  /// 경고가 나온 횟수 (결과 기록의 incorrectReps).
  final int badCount;

  /// 이 세트에서 나온 서로 다른 경고 종류 수 (set_summary 의 {k}).
  final int fixCount;
}

/// 브레이크 타임 화면: 세트 사이 휴식 타이머 + 코리 코멘트 + 세트별 기록.
class _BreakTimeOverlay extends StatelessWidget {
  const _BreakTimeOverlay({
    required this.isKo,
    required this.exerciseName,
    required this.completedSet,
    required this.totalSets,
    required this.restRemaining,
    required this.restTotal,
    required this.setResults,
    required this.plannedReps,
    required this.plannedWeightsKg,
    required this.onAdjustRest,
    required this.onSkipRest,
    required this.onNext,
  });

  final bool isKo;
  final String exerciseName;
  final int completedSet;
  final int totalSets;
  final int restRemaining;
  final int restTotal;
  final List<_SetResult> setResults;
  final List<int> plannedReps;
  final List<int> plannedWeightsKg;
  final ValueChanged<int> onAdjustRest;
  final VoidCallback onSkipRest;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final lastResult = setResults.isEmpty ? null : setResults.last;
    return Container(
      color: AppColors.black,
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    exerciseName,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isKo
                          ? '$completedSet / $totalSets세트 완료'
                          : '$completedSet / $totalSets sets done',
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  isKo ? '숨 좀 돌리자!' : 'Catch your breath!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: _RestRing(
                  isKo: isKo,
                  remaining: restRemaining,
                  total: restTotal,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RestAdjustButton(
                    label: isKo ? '-15초' : '-15s',
                    onTap: () => onAdjustRest(-15),
                  ),
                  const SizedBox(width: 10),
                  _RestAdjustButton(
                    label: isKo ? '+15초' : '+15s',
                    onTap: () => onAdjustRest(15),
                  ),
                  const SizedBox(width: 10),
                  _RestAdjustButton(
                    label: isKo ? '바로 할래' : 'Skip',
                    onTap: onSkipRest,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _KoriBreakMessage(
                isKo: isKo,
                reps: lastResult?.reps ?? 0,
                fixCount: lastResult?.fixCount ?? 0,
              ),
              const SizedBox(height: 16),
              _SoFarCard(
                isKo: isKo,
                results: setResults,
                completedSet: completedSet,
                totalSets: totalSets,
                plannedReps: plannedReps,
                plannedWeightsKg: plannedWeightsKg,
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onNext,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    isKo
                        ? '${completedSet + 1}세트 시작'
                        : 'Start set ${completedSet + 1}',
                    style: const TextStyle(
                      color: AppColors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 휴식 시간 원형 타이머. 남은 시간이 줄어들수록 링이 채워지며 애니메이션된다.
class _RestRing extends StatefulWidget {
  const _RestRing({
    required this.isKo,
    required this.remaining,
    required this.total,
  });
  final bool isKo;
  final int remaining;
  final int total;

  @override
  State<_RestRing> createState() => _RestRingState();
}

class _RestRingState extends State<_RestRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  double get _progress {
    if (widget.total <= 0) return 1;
    return (1 - widget.remaining / widget.total).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animation = AlwaysStoppedAnimation(_progress);
  }

  @override
  void didUpdateWidget(covariant _RestRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remaining != widget.remaining ||
        oldWidget.total != widget.total) {
      _animation = Tween<double>(begin: _animation.value, end: _progress)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _label {
    final m = (widget.remaining ~/ 60).toString().padLeft(2, '0');
    final s = (widget.remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: CircularProgressIndicator(
                  value: _animation.value,
                  strokeWidth: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(AppColors.green),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      // w900는 폰트가 지원하는 최대 굵기라, 안쪽을 살짝 두껍게
                      // 덧그려서(faux bold) 실제로 더 두꺼워 보이게 만든다.
                      Text(
                        _label,
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 2
                            ..color = Colors.white,
                        ),
                      ),
                      Text(
                        _label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isKo ? '남은 휴식' : 'Rest left',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RestAdjustButton extends StatefulWidget {
  const _RestAdjustButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_RestAdjustButton> createState() => _RestAdjustButtonState();
}

class _RestAdjustButtonState extends State<_RestAdjustButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.92 : 1,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: Material(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.green.withValues(alpha: 0.45),
          highlightColor: AppColors.green.withValues(alpha: 0.25),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 방금 끝낸 세트에 대한 코리의 코멘트 (idle 상태와 같은 보라색 말풍선 스타일).
class _KoriBreakMessage extends StatelessWidget {
  const _KoriBreakMessage({
    required this.isKo,
    required this.reps,
    required this.fixCount,
  });
  final bool isKo;
  final int reps;
  final int fixCount;

  @override
  Widget build(BuildContext context) {
    // 경고 없이 끝난 세트 → praise_clean_set, 경고가 있었으면 → set_summary.
    final line = fixCount == 0
        ? koriFeedbackLines['praise_clean_set']!
        : koriFeedbackLines['set_summary']!;
    final (:title, :subtitle) =
        splitKoriLine(line.render(isKo: isKo, reps: reps, k: fixCount));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 18, 14),
      decoration: const BoxDecoration(
        color: AppColors.purple,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/character/face2.png',
            width: 64,
            height: 64,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const double _soFarRowHeight = 40;

/// "지금까지" 세트 기록 카드. 최대 3줄만 보이고, 방금 끝낸 세트가 가운데 오도록
/// 자동 스크롤되며, 그 밖의 세트는 카드 안에서 위/아래로 스크롤해 볼 수 있다.
class _SoFarCard extends StatefulWidget {
  const _SoFarCard({
    required this.isKo,
    required this.results,
    required this.completedSet,
    required this.totalSets,
    required this.plannedReps,
    required this.plannedWeightsKg,
  });
  final bool isKo;
  final List<_SetResult> results;
  final int completedSet;
  final int totalSets;
  // 아직 안 한 세트는 계획된 반복 수·무게를 보여준다.
  final List<int> plannedReps;
  final List<int> plannedWeightsKg;

  @override
  State<_SoFarCard> createState() => _SoFarCardState();
}

class _SoFarCardState extends State<_SoFarCard> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerCompleted());
  }

  @override
  void didUpdateWidget(covariant _SoFarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.completedSet != widget.completedSet) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerCompleted());
    }
  }

  void _centerCompleted() {
    if (!_scrollController.hasClients) return;
    final targetIndex = widget.completedSet - 1; // 0-based
    final desired = (targetIndex - 1) * _soFarRowHeight;
    final maxExtent = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      desired.clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = widget.totalSets < 3 ? widget.totalSets : 3;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isKo ? '지금까지' : 'So far',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: _soFarRowHeight * visibleRows,
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemExtent: _soFarRowHeight,
              itemCount: widget.totalSets,
              itemBuilder: (context, index) {
                final setNumber = index + 1;
                final done = setNumber <= widget.completedSet;
                final result = done ? widget.results[index] : null;
                return _SetRow(
                  isKo: widget.isKo,
                  setNumber: setNumber,
                  done: done,
                  reps: result?.reps ??
                      (index < widget.plannedReps.length
                          ? widget.plannedReps[index]
                          : 0),
                  weightKg: result?.weightKg ??
                      (index < widget.plannedWeightsKg.length
                          ? widget.plannedWeightsKg[index]
                          : 0),
                  badCount: result?.badCount ?? 0,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.isKo,
    required this.setNumber,
    required this.done,
    required this.reps,
    required this.weightKg,
    required this.badCount,
  });
  final bool isKo;
  final int setNumber;
  final bool done;
  final int reps;
  final int weightKg;
  final int badCount;

  @override
  Widget build(BuildContext context) {
    final String? trailingText;
    final Color trailingColor;
    if (!done) {
      trailingText = null;
      trailingColor = Colors.transparent;
    } else if (badCount == 0) {
      trailingText = isKo ? '완벽해' : 'Perfect';
      trailingColor = AppColors.green;
    } else {
      trailingText = isKo ? '교정 $badCount회' : 'Fix x$badCount';
      trailingColor = AppColors.pink;
    }

    return SizedBox(
      height: _soFarRowHeight,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  done ? AppColors.green : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$setNumber',
              style: TextStyle(
                color: done
                    ? AppColors.black
                    : Colors.white.withValues(alpha: 0.4),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isKo
                ? '$reps회 · ${weightKg}kg${done ? '' : ' 예정'}'
                : '$reps reps · ${weightKg}kg${done ? '' : ' upcoming'}',
            style: TextStyle(
              color: done ? Colors.white : Colors.white.withValues(alpha: 0.35),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (trailingText != null)
            Text(
              trailingText,
              style: TextStyle(
                color: trailingColor,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

/// Final overlay shown after the last set is finished.
/// 코리가 튀어나오며 등장하고, 위쪽에서 폭죽 조각이 터진다.
class _WorkoutCompleteOverlay extends StatefulWidget {
  const _WorkoutCompleteOverlay({
    required this.totalSets,
    required this.isKo,
    required this.onFinish,
  });

  final int totalSets;
  final bool isKo;
  final VoidCallback onFinish;

  @override
  State<_WorkoutCompleteOverlay> createState() =>
      _WorkoutCompleteOverlayState();
}

class _WorkoutCompleteOverlayState extends State<_WorkoutCompleteOverlay>
    with SingleTickerProviderStateMixin {
  static const _totalDuration = Duration(milliseconds: 3200);

  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: _totalDuration)..forward();
  late final List<_ConfettiPiece> _pieces =
      _ConfettiPiece.bursts(math.Random());

  // 코리: 처음 0.6초 동안 통통 튀며 커진다.
  late final Animation<double> _koriScale = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0, 0.2, curve: Curves.elasticOut),
  );
  // 글씨·버튼: 코리 뒤에 이어서 서서히 나타난다.
  late final Animation<double> _textFade = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.1, 0.3, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isKo = widget.isKo;
    final title = isKo ? '운동 끝! 해냈다!' : 'Workout done!';
    final subtitle = isKo
        ? '${widget.totalSets}세트 전부 해치웠어.\n오늘도 진짜 수고했어!'
        : 'You crushed all ${widget.totalSets} sets.\nAwesome work today!';
    final btnLabel = isKo ? '결과 보러 가기' : 'See my results';

    return Container(
      color: AppColors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                children: [
                  const Spacer(),
                  // 코리
                  ScaleTransition(
                    scale: _koriScale,
                    child: SizedBox(
                      width: 260,
                      height: 280,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            'assets/images/character/congrats.png',
                            height: 270,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _textFade,
                    child: Column(
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  FadeTransition(
                    opacity: _textFade,
                    child: GestureDetector(
                      onTap: widget.onFinish,
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          btnLabel,
                          style: const TextStyle(
                            color: AppColors.black,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 폭죽 (터치는 뒤로 통과)
          IgnorePointer(
            child: CustomPaint(
              painter: _ConfettiPainter(
                pieces: _pieces,
                animation: _ctrl,
                totalSeconds: _totalDuration.inMilliseconds / 1000,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 폭죽 조각 하나. 위치·속도는 화면 크기 비율(0~1) 기준이라 기기 크기와 무관하다.
class _ConfettiPiece {
  _ConfettiPiece({
    required this.origin,
    required this.velocity,
    required this.delay,
    required this.color,
    required this.size,
    required this.spin,
    required this.isCircle,
  });

  final Offset origin;
  final Offset velocity; // 화면 비율 / 초
  final double delay; // 초
  final Color color;
  final double size;
  final double spin; // 회전 속도 (rad/s)
  final bool isCircle;

  static const _colors = [
    AppColors.green,
    AppColors.purple,
    AppColors.pink,
    AppColors.red,
    AppColors.white,
  ];

  // 화면 위쪽 세 지점에서 시간차를 두고 터진다.
  static List<_ConfettiPiece> bursts(math.Random rng) {
    const centers = [Offset(0.5, 0.22), Offset(0.22, 0.3), Offset(0.78, 0.28)];
    const delays = [0.1, 0.45, 0.8];
    final pieces = <_ConfettiPiece>[];
    for (var b = 0; b < centers.length; b++) {
      for (var i = 0; i < 38; i++) {
        final angle = rng.nextDouble() * math.pi * 2;
        final speed = 0.25 + rng.nextDouble() * 0.45;
        pieces.add(_ConfettiPiece(
          origin: centers[b],
          // 위로 조금 더 튀도록 y 속도를 보정한다.
          velocity: Offset(
              math.cos(angle) * speed * 0.8, math.sin(angle) * speed - 0.25),
          delay: delays[b] + rng.nextDouble() * 0.08,
          color: _colors[rng.nextInt(_colors.length)],
          size: 5 + rng.nextDouble() * 6,
          spin: (rng.nextDouble() - 0.5) * 14,
          isCircle: rng.nextDouble() < 0.35,
        ));
      }
    }
    return pieces;
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.pieces,
    required this.animation,
    required this.totalSeconds,
  }) : super(repaint: animation);

  final List<_ConfettiPiece> pieces;
  final Animation<double> animation;
  final double totalSeconds;

  static const _gravity = 0.9; // 화면 비율 / 초²
  static const _life = 1.8; // 조각 하나가 보이는 시간(초)

  @override
  void paint(Canvas canvas, Size size) {
    final now = animation.value * totalSeconds;
    final paint = Paint();
    for (final p in pieces) {
      final t = now - p.delay;
      if (t <= 0 || t >= _life) continue;
      // 공기 저항처럼 점점 느려지는 수평 이동 + 중력 낙하
      final drag = 1 - math.exp(-2.2 * t);
      final x = p.origin.dx + p.velocity.dx * drag / 2.2;
      final y = p.origin.dy +
          p.velocity.dy * drag / 2.2 +
          0.5 * _gravity * t * t * 0.5;
      final fade =
          t > _life * 0.6 ? 1 - (t - _life * 0.6) / (_life * 0.4) : 1.0;
      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(p.spin * t);
      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: p.size, height: p.size * 0.55),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
