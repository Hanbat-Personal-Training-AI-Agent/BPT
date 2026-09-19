import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/mock_data.dart';

/// Preparation phases shown before the native camera PlatformView appears.
enum _PrepPhase { alignHint, countdown, live }

class NativePoseWorkoutScreen extends ConsumerStatefulWidget {
  const NativePoseWorkoutScreen({
    super.key,
    required this.exerciseId,
    this.targetReps = 15,
    this.targetSets = 3,
  });

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

  // 코리 피드백: 실제 자세 평가 연동 전까지 rep마다 good/more deep을 번갈아 보여준다.
  // 첫 rep이 잡히기 전까지는 "준비되면 시작해보자!" 기본 멘트를 보여준다.
  bool _feedbackGood = true;
  bool _hasFeedbackStarted = false;

  bool get _isSupportedExercise =>
      NativePoseWorkoutScreen.supportedExerciseIds.contains(widget.exerciseId);
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  int get _repsThisSet {
    final v = _latestNativeRep - _setStartRep;
    if (v < 0) return 0;
    if (v > widget.targetReps) return widget.targetReps;
    return v;
  }

  int get _completedWorkoutReps {
    final completedSets = (_currentSet - 1).clamp(0, widget.targetSets);
    final total = completedSets * widget.targetReps + _repsThisSet;
    return total.clamp(0, widget.targetReps * widget.targetSets);
  }

  @override
  void initState() {
    super.initState();
    // Only run the prep/countdown flow when we will actually show the camera.
    if (_isSupportedExercise && _isIOS) {
      _alignTimer = Timer(_alignHintDuration, _startCountdown);
    }
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
    }
    return null;
  }

  void _onNativeUpdate(int rep) {
    if (!mounted || _isPaused) return;
    setState(() {
      final repIncreased = rep > _latestNativeRep;
      _latestNativeRep = rep;
      // Don't advance set state while a set-complete / done prompt is showing;
      // reps performed during the rest period are discarded on "next set".
      if (_setComplete || _workoutComplete) return;
      if (repIncreased) {
        _feedbackGood = !_feedbackGood;
        _hasFeedbackStarted = true;
      }
      if (rep - _setStartRep >= widget.targetReps) {
        if (_currentSet < widget.targetSets) {
          _setComplete = true;
        } else {
          _workoutComplete = true;
        }
      }
    });
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
  }

  void _startNextSet() {
    setState(() {
      _currentSet += 1;
      _setStartRep = _latestNativeRep; // snapshot: discard rest-period reps
      _setComplete = false;
    });
  }

  void _finishWorkout() {
    if (!mounted) return;

    final exercise = findExercise(widget.exerciseId);
    final elapsedSeconds = _liveStartedAt == null
        ? 0
        : DateTime.now().difference(_liveStartedAt!).inSeconds;

    context.pushReplacement(
      RouteConstants.workoutResult,
      extra: {
        'exerciseId': widget.exerciseId,
        'exerciseName': exercise.name,
        'exerciseNameKr': exercise.nameKr,
        'totalReps': _completedWorkoutReps,
        'correctReps': null,
        'incorrectReps': null,
        'elapsedSeconds': elapsedSeconds,
        'postureScore': null,
        'feedbackHistory': null,
        'targetReps': widget.targetReps * widget.targetSets,
        'targetSets': widget.targetSets,
      },
    );
  }

  @override
  void dispose() {
    _alignTimer?.cancel();
    _countdownTimer?.cancel();
    _elapsedTimer?.cancel();
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
    final isLiveTracking = _isSupportedExercise &&
        _isIOS &&
        _phase == _PrepPhase.live &&
        !_setComplete &&
        !_workoutComplete;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(context, exName, isKo)),
          if (!isLiveTracking)
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
    );
  }

  Widget _buildBody(
    BuildContext context,
    String exerciseName,
    bool isKo,
  ) {
    if (!_isSupportedExercise) {
      return _MessageState(
        icon: Icons.error_outline_rounded,
        title: '지원하지 않는 운동입니다.',
        message: 'exerciseId: ${widget.exerciseId}',
      );
    }

    if (!_isIOS) {
      return const _MessageState(
        icon: Icons.phone_iphone_rounded,
        title: 'iOS 전용 기능',
        message: '실시간 AI 카메라 코칭은 현재 iOS에서만 사용할 수 있습니다.',
      );
    }

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
        UiKitView(
          viewType: NativePoseWorkoutScreen.viewType,
          creationParams: {'exerciseId': widget.exerciseId},
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
        if (!_setComplete && !_workoutComplete)
          Positioned.fill(
            child: SafeArea(
              child: _LiveHud(
                isKo: isKo,
                exerciseId: widget.exerciseId,
                exerciseName: exerciseName,
                elapsedSeconds: _elapsedSeconds,
                reps: _repsThisSet,
                targetReps: widget.targetReps,
                currentSet: _currentSet,
                totalSets: widget.targetSets,
                feedbackIdle: !_hasFeedbackStarted,
                feedbackGood: _feedbackGood,
                isPaused: _isPaused,
                onTogglePause: _togglePause,
                onEnd: _finishWorkout,
              ),
            ),
          ),
        if (_setComplete)
          _SetCompleteOverlay(
            completedSet: _currentSet,
            nextSet: _currentSet + 1,
            totalSets: widget.targetSets,
            isKo: isKo,
            onNext: _startNextSet,
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
    required this.feedbackIdle,
    required this.feedbackGood,
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
  final bool feedbackIdle;
  final bool feedbackGood;
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
            idle: feedbackIdle,
            good: feedbackGood,
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
              Expanded(
                child: _PauseButton(
                  isKo: isKo,
                  isPaused: isPaused,
                  onTap: onTogglePause,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _EndButton(isKo: isKo, onTap: onEnd)),
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

/// 코리가 rep마다 보여주는 임시 피드백 말풍선 (실제 자세 평가 연동 전 placeholder).
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
    required this.idle,
    required this.good,
  });
  final bool isKo;
  final String exerciseId;
  final bool idle;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final String characterAsset;
    final Color bubbleColor;
    final Color textColor;
    final String title;
    final String subtitle;

    if (idle) {
      characterAsset = 'assets/images/character/considering.png';
      bubbleColor = AppColors.purple;
      textColor = AppColors.black;
      title = isKo ? '준비되면 시작해보자!' : "Start whenever you're ready!";
      subtitle = isKo
          ? (_idleTipsKo[exerciseId] ?? _idleTipsKo['squat']!)
          : (_idleTipsEn[exerciseId] ?? _idleTipsEn['squat']!);
    } else if (good) {
      characterAsset = 'assets/images/character/cheering.png';
      bubbleColor = AppColors.green;
      textColor = AppColors.black;
      title = isKo ? '좋아! 자세 정확해' : 'Nice! Great form';
      subtitle = isKo ? '지금처럼만 유지해' : 'Keep it up just like this';
    } else {
      characterAsset = 'assets/images/character/worrying.png';
      bubbleColor = AppColors.pink;
      textColor = AppColors.white;
      title = isKo ? '잠깐! 무릎이 너무 안쪽으로 모였어' : 'Wait! Your knees caved in';
      subtitle = isKo ? '발끝 방향으로 살짝 벌려줘' : 'Push them out toward your toes';
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
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              isPaused
                  ? (isKo ? '이어서 하기' : 'Resume')
                  : (isKo ? '잠깐 쉬기' : 'Pause'),
              style: const TextStyle(
                color: Colors.white,
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
          color: AppColors.pink,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          isKo ? '끝내기' : 'End',
          style: const TextStyle(
            color: AppColors.black,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// Set-complete prompt asking the user to continue to the next set.
class _SetCompleteOverlay extends StatelessWidget {
  const _SetCompleteOverlay({
    required this.completedSet,
    required this.nextSet,
    required this.totalSets,
    required this.isKo,
    required this.onNext,
  });

  final int completedSet;
  final int nextSet;
  final int totalSets;
  final bool isKo;
  final VoidCallback onNext;

  String _ordinalKr(int n) {
    const names = ['', '첫번째', '두번째', '세번째', '네번째', '다섯번째'];
    if (n < names.length) return names[n];
    return '$n번째';
  }

  String _ordinalEn(int n) {
    if (n == 1) return '1st';
    if (n == 2) return '2nd';
    if (n == 3) return '3rd';
    return '${n}th';
  }

  @override
  Widget build(BuildContext context) {
    final completedLabel =
        isKo ? _ordinalKr(completedSet) : _ordinalEn(completedSet);
    final nextLabel = isKo ? _ordinalKr(nextSet) : _ordinalEn(nextSet);

    final title =
        isKo ? '$completedLabel 세트 완료!' : 'Set $completedSet Complete!';
    final subtitle = isKo
        ? '$nextLabel 세트를 시작하려면 아래 버튼을 눌러주세요'
        : 'Press the button below to start set $nextSet';
    final btnLabel = isKo ? '$nextLabel 세트 시작하기' : 'Start Set $nextSet';

    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.primary, width: 2.5),
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isKo
                    ? '$completedSet / $totalSets 세트 완료'
                    : '$completedSet / $totalSets sets done',
                style: TextStyle(
                  color: AppColors.primary.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    btnLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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

/// Final overlay shown after the last set is finished.
class _WorkoutCompleteOverlay extends StatelessWidget {
  const _WorkoutCompleteOverlay({
    required this.totalSets,
    required this.isKo,
    required this.onFinish,
  });

  final int totalSets;
  final bool isKo;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final title = isKo ? '운동 완료!' : 'Workout Complete!';
    final subtitle = isKo
        ? '$totalSets 세트를 모두 마쳤어요. 수고하셨습니다!'
        : 'You finished all $totalSets sets. Great job!';
    final btnLabel = isKo ? '완료' : 'Finish';

    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.primary, width: 2.5),
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    btnLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
