import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import '../services/calibration_upload_service.dart';
import '../widgets/calibration_silhouette.dart';

/// Full-screen body calibration capture: shown after the user taps "카메라 켜기"
/// on [OnboardingCaptureScreen].
///
/// The native `bpt/body_scan_camera` PlatformView owns the camera, RTMPose-s and the
/// judging engine; this screen starts it with the user's height, renders the A-pose
/// silhouette guide plus the guidance it reports, and leaves for the analysis step
/// once all four views are in the session folder.
class OnboardingScanScreen extends ConsumerStatefulWidget {
  const OnboardingScanScreen({super.key});

  static const String viewType = 'bpt/body_scan_camera';

  @override
  ConsumerState<OnboardingScanScreen> createState() => _OnboardingScanScreenState();
}

class _OnboardingScanScreenState extends ConsumerState<OnboardingScanScreen> {
  MethodChannel? _channel;
  CalibrationSilhouettes? _silhouettes;

  /// Latest line from the native judging engine; null until the camera reports in.
  String? _guidance;
  String? _targetView = 'front';
  List<String> _capturedViews = const [];
  CalibrationGuide _guide = const CalibrationGuide();
  CalibrationPerson? _person;
  DateTime _personSeenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// A frame without a measurement (phone gate, one lost joint) keeps the last outline this long,
  /// so the guide does not jump to its empty-frame spot and back.
  static const _personHold = Duration(milliseconds: 500);
  double _holdProgress = 0;
  bool _isPassing = false;
  String? _error;
  bool _finished = false;

  /// White flash over the preview each time a view is captured.
  bool _flash = false;

  /// The "…찍었어!" line arrives on a single frame; keep it in the bubble for the
  /// capture cooldown so it can be read, not just heard.
  static const _captureLineHold = Duration(milliseconds: 1500);
  String? _captureLine;
  DateTime _captureLineUntil = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    // The GPU container starts while the user is being photographed (~65 s cold start).
    ref.read(calibrationUploadServiceProvider).warmUp();
    CalibrationSilhouettes.load().then((value) {
      if (mounted) setState(() => _silhouettes = value);
    });
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('${OnboardingScanScreen.viewType}/$id');
    _channel!.setMethodCallHandler(_handleNativeCall);
    _channel!.invokeMethod<void>('start', {
      'userHeightCm': ref.read(onboardingProvider).heightCm,
    });
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (!mounted) return null;
    switch (call.method) {
      case 'onCalibrationUpdate':
        final args = (call.arguments as Map).cast<String, dynamic>();
        final sessionPath = args['sessionPath'] as String?;
        final captured =
            (args['capturedViews'] as List?)?.cast<String>() ?? _capturedViews;
        final newCapture = captured.length > _capturedViews.length;
        setState(() {
          _guidance = args['guidance'] as String?;
          _targetView = args['targetView'] as String?;
          _capturedViews = captured;
          _guide = CalibrationGuide.fromMap((args['guide'] as Map?)?.cast<String, dynamic>());
          final person = CalibrationPerson.fromMap((args['person'] as Map?)?.cast<String, dynamic>());
          final now = DateTime.now();
          if (person != null) {
            _person = person;
            _personSeenAt = now;
          } else if (now.difference(_personSeenAt) >= _personHold) {
            _person = null;
          }
          _holdProgress = (args['holdProgress'] as num?)?.toDouble() ?? 0;
          _isPassing = args['isPassing'] as bool? ?? false;
          if (newCapture) {
            _flash = true;
            _captureLine = _guidance;
            _captureLineUntil = DateTime.now().add(_captureLineHold);
          }
        });
        if (newCapture) {
          Future.delayed(const Duration(milliseconds: 120), () {
            if (mounted) setState(() => _flash = false);
          });
        }
        if (args['isFinished'] == true && sessionPath != null && !_finished) {
          _finished = true;
          // 4장을 다 찍은 시점이 체형 측정일이다 (POST /users/me/body-scan).
          unawaited(ref
              .read(authNotifierProvider)
              .recordBodyScan(sessionPath: sessionPath));
          context.go(RouteConstants.onboardingAnalyzing, extra: sessionPath);
        }
      case 'onCalibrationError':
        final args = (call.arguments as Map).cast<String, dynamic>();
        setState(() => _error = args['error'] as String?);
    }
    return null;
  }

  // TODO(temp): 시뮬레이터에는 카메라가 없어서 촬영이 진행되지 않으므로,
  // 누를 때마다 지금 방향을 찍은 것처럼 정면 → 왼쪽 → 뒷면 → 오른쪽 순서로 넘기는
  // 테스트용 동작. 4장째에서 분석 화면으로 간다 (촬영 데이터가 없어 업로드는 건너뜀).
  void _debugCaptureNext() {
    if (_finished) return;
    const views = CalibrationScanOverlay.views;
    final captured = [..._capturedViews, views[_capturedViews.length]];
    setState(() {
      _capturedViews = captured;
      _targetView =
          captured.length < views.length ? views[captured.length] : null;
      _flash = true;
    });
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _flash = false);
    });
    if (captured.length < views.length) return;
    _channel?.invokeMethod<void>('cancel');
    _finished = true;
    unawaited(ref.read(authNotifierProvider).recordBodyScan());
    context.go(RouteConstants.onboardingAnalyzing);
  }

  void _cancel() {
    _channel?.invokeMethod<void>('cancel');
    context.pop();
  }

  void _showHelp() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.grey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('촬영 팁',
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            SizedBox(height: 16),
            _HelpTip('폰은 세로로 세워 고정해 줘. 바닥에 둘 땐 살짝 뒤로 기대도 돼'),
            SizedBox(height: 10),
            _HelpTip('머리부터 발끝까지 화면에 다 나오게 서 줘'),
            SizedBox(height: 10),
            _HelpTip('팔은 몸에서 떼서 A자로, 팔꿈치는 쭉 펴 줘'),
            SizedBox(height: 10),
            _HelpTip('처음 선 자리에서 발 떼지 말고 제자리에서 돌아 줘'),
            SizedBox(height: 10),
            _HelpTip('몸에 붙는 옷이면 더 정확해'),
            SizedBox(height: 10),
            _HelpTip('등을 보일 땐 화면이 안 보이니까 소리를 들어 줘'),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Leaving mid-run (back swipe) throws the partial session away; a finished one is kept.
    if (!_finished) _channel?.invokeMethod<void>('cancel');
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CalibrationScanOverlay(
      // Camera fills the screen edge to edge; everything else floats on top of it.
      preview: _isIOS
          ? UiKitView(
              viewType: OnboardingScanScreen.viewType,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onPlatformViewCreated,
            )
          : Container(color: AppColors.grey),
      silhouettes: _silhouettes,
      guidance: _error != null
          ? _errorMessage(_error!)
          : DateTime.now().isBefore(_captureLineUntil)
              ? _captureLine
              : _guidance,
      targetView: _targetView,
      capturedViews: _capturedViews,
      guide: _guide,
      person: _person,
      holdProgress: _holdProgress,
      isPassing: _isPassing,
      flash: _flash,
      onClose: _cancel,
      onHelp: _showHelp,
      onDebugCapture: kDebugMode ? _debugCaptureNext : null,
    );
  }

  String _errorMessage(String error) => switch (error) {
        'camera_permission_denied' => '설정에서 카메라 권한을 켜줘',
        _ => '카메라를 시작하지 못했어. 다시 시도해줘',
      };
}

/// Everything drawn over the camera: header, progress, the A-pose guide, Kori's bubble
/// and the view chips. Pure presentation, so the same widget can be fed recorded
/// states (see tool/calibration_mock_video_test.dart) as well as live native events.
class CalibrationScanOverlay extends StatelessWidget {
  const CalibrationScanOverlay({
    super.key,
    required this.preview,
    required this.silhouettes,
    required this.guidance,
    required this.targetView,
    required this.capturedViews,
    this.guide = const CalibrationGuide(),
    this.person,
    required this.holdProgress,
    required this.isPassing,
    required this.flash,
    this.onClose,
    this.onHelp,
    this.onDebugCapture,
  });

  /// Capture order the guidance recommends: one continuous turn to the user's left.
  ///
  /// Keys are the saved view labels (which side of the body the camera sees);
  /// the chip labels name the way the user turns, so "왼쪽" is `rightfront`.
  static const views = ['front', 'rightfront', 'back', 'leftfront'];
  static const viewLabels = {
    'front': '정면',
    'rightfront': '왼쪽',
    'back': '뒷면',
    'leftfront': '오른쪽',
  };

  final Widget preview;
  final CalibrationSilhouettes? silhouettes;

  /// Latest line from the native judging engine; null until the camera reports in.
  final String? guidance;
  final String? targetView;
  final List<String> capturedViews;

  /// The engine's framing target and where it measured the user; the outline is drawn from these.
  final CalibrationGuide guide;
  final CalibrationPerson? person;
  final double holdProgress;
  final bool isPassing;

  /// White flash over the preview each time a view is captured.
  final bool flash;
  final VoidCallback? onClose;
  final VoidCallback? onHelp;

  /// 디버그 빌드에서만 넘긴다: 지금 방향을 찍은 것으로 넘기는 테스트 버튼.
  final VoidCallback? onDebugCapture;

  @override
  Widget build(BuildContext context) {
    final currentIndex = capturedViews.length.clamp(0, views.length - 1);
    final view = targetView ?? views[currentIndex];
    final label = viewLabels[view]!;

    return Theme(
      data: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Pretendard'),
        scaffoldBackgroundColor: AppColors.black,
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Camera fills the entire screen edge-to-edge; every other
            // element below floats on top of it as an overlay.
            preview,
            if (silhouettes != null)
              IgnorePointer(
                child: CalibrationGuideOverlay(
                  silhouettes: silhouettes!,
                  view: targetView,
                  guide: guide,
                  person: person,
                  isPassing: isPassing,
                  progress: holdProgress,
                ),
              ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: flash ? 0.85 : 0,
                duration: Duration(milliseconds: flash ? 40 : 260),
                child: const ColoredBox(color: Colors.white),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '닫기',
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded,
                              color: AppColors.white, size: 24),
                        ),
                        Expanded(
                          child: Text(
                            '${currentIndex + 1} / ${views.length} · $label',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        GestureDetector(
                          onTap: onHelp,
                          child: const Text('도움말',
                              style: TextStyle(
                                  color: Color(0xFF9AA0A6),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        for (var i = 0; i < views.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: capturedViews.contains(views[i]) ? 1 : 0,
                                minHeight: 5,
                                backgroundColor: AppColors.grey,
                                valueColor: const AlwaysStoppedAnimation(
                                    AppColors.green),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 몸을 가리지 않게 코리 말풍선은 위, 촬영 상태 버튼은 아래에 둔다.
                  if (guidance != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: _StatusBubble(
                        message: guidance!,
                        holdProgress: holdProgress,
                      ),
                    ),
                  const Spacer(),
                  if (onDebugCapture != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _DebugButton(
                            label: '$label 촬영 완료 (테스트용)',
                            onTap: onDebugCapture!),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        for (var i = 0; i < views.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: _PoseChip(
                              label: viewLabels[views[i]]!,
                              state: capturedViews.contains(views[i])
                                  ? _ChipState.done
                                  : views[i] == targetView
                                      ? _ChipState.active
                                      : _ChipState.waiting,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 코리 말풍선(알약 모양): 판정 엔진의 지금 안내 한 줄과, 자세를 유지하는 동안 진행 원.
class _StatusBubble extends StatelessWidget {
  const _StatusBubble({required this.message, required this.holdProgress});

  final String message;
  final double holdProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/character/face.png',
              width: 26,
              height: 30,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                    color: AppColors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.3),
              ),
            ),
            if (holdProgress > 0) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: holdProgress,
                  strokeWidth: 3.5,
                  backgroundColor: AppColors.black.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation(AppColors.black),
                ),
              ),
            ] else
              const SizedBox(width: 4),
          ],
        ),
      ),
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

enum _ChipState { done, active, waiting }

class _PoseChip extends StatelessWidget {
  const _PoseChip({required this.label, required this.state});

  final String label;
  final _ChipState state;

  @override
  Widget build(BuildContext context) {
    final (text, background, textColor) = switch (state) {
      _ChipState.done => ('$label 완료', const Color(0xFF1E1E1E), AppColors.pink),
      _ChipState.active => ('$label 촬영 중', AppColors.purple, AppColors.black),
      _ChipState.waiting => (label, const Color(0xFF1E1E1E), const Color(0xFF6B6B6B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
      decoration:
          BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      // 좁은 화면에서도 한 줄을 지키도록 넘치면 글자를 줄인다.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text,
            maxLines: 1,
            style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4)),
      ),
    );
  }
}

class _HelpTip extends StatelessWidget {
  const _HelpTip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: AppColors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: AppColors.black, size: 13),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      );
}
