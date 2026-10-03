import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/onboarding_provider.dart';
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
          context.go(RouteConstants.onboardingAnalyzing, extra: sessionPath);
        }
      case 'onCalibrationError':
        final args = (call.arguments as Map).cast<String, dynamic>();
        setState(() => _error = args['error'] as String?);
    }
    return null;
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
            _HelpTip('폰은 세로로 똑바로 세워서 고정해 줘'),
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
      holdProgress: _holdProgress,
      isPassing: _isPassing,
      flash: _flash,
      onClose: _cancel,
      onHelp: _showHelp,
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
    required this.holdProgress,
    required this.isPassing,
    required this.flash,
    this.onClose,
    this.onHelp,
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
  static const viewHints = {
    'front': '카메라 보고 팔은 A자로,\n발은 어깨너비로 벌려 줘!',
    'rightfront': '제자리에서 왼쪽으로 비스듬히 돌아 줘.\n고개도 몸이랑 같은 방향으로!',
    'back': '이번엔 등을 보여 줘.\n팔은 계속 A자 유지!',
    'leftfront': '마지막! 오른쪽으로 비스듬히 돌아 줘.\n거의 다 왔어!',
  };

  final Widget preview;
  final CalibrationSilhouettes? silhouettes;

  /// Latest line from the native judging engine; null until the camera reports in.
  final String? guidance;
  final String? targetView;
  final List<String> capturedViews;
  final double holdProgress;
  final bool isPassing;

  /// White flash over the preview each time a view is captured.
  final bool flash;
  final VoidCallback? onClose;
  final VoidCallback? onHelp;

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
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 3 / 5,
                          child: IgnorePointer(
                            child: silhouettes == null
                                ? const SizedBox.shrink()
                                : CustomPaint(
                                    size: Size.infinite,
                                    painter: CalibrationSilhouettePainter(
                                      silhouettes: silhouettes!,
                                      view: targetView,
                                      isPassing: isPassing,
                                      progress: holdProgress,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: _StatusBubble(
                      message: guidance,
                      hint: viewHints[view]!,
                      holdProgress: holdProgress,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        for (var i = 0; i < views.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
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

/// Kori's speech bubble: the live guidance from the judging engine on top, the
/// per-view instruction underneath (alone until the camera reports in).
class _StatusBubble extends StatelessWidget {
  const _StatusBubble(
      {required this.message, required this.hint, required this.holdProgress});

  final String? message;
  final String hint;
  final double holdProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/character/face.png',
            width: 44,
            height: 48,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message != null)
                  Text(
                    message!,
                    style: const TextStyle(
                        color: AppColors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.4),
                  ),
                Text(
                  hint,
                  style: TextStyle(
                      color: AppColors.black,
                      fontWeight: message == null ? FontWeight.w800 : FontWeight.w600,
                      fontSize: message == null ? 13 : 12,
                      height: 1.4),
                ),
              ],
            ),
          ),
          if (holdProgress > 0) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                value: holdProgress,
                strokeWidth: 4,
                backgroundColor: AppColors.black.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(AppColors.black),
              ),
            ),
          ],
        ],
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
    final background = state == _ChipState.active
        ? AppColors.purple
        : const Color(0xFF1E1E1E);

    if (state == _ChipState.done) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration:
            BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
        child: Text('$label 완료',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.pink, fontSize: 11, fontWeight: FontWeight.w700)),
      );
    }

    final statusWord = state == _ChipState.active ? '촬영 중' : '대기 중';
    final textColor =
        state == _ChipState.active ? AppColors.black : const Color(0xFF6B6B6B);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration:
          BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: textColor, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(statusWord,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: textColor, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
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
