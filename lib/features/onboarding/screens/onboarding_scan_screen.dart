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
  /// Capture order the guidance recommends: one continuous turn.
  static const _views = ['front', 'leftfront', 'back', 'rightfront'];
  static const _viewLabels = {
    'front': '정면',
    'leftfront': '왼쪽 옆면',
    'rightfront': '오른쪽 옆면',
    'back': '뒷면',
  };

  MethodChannel? _channel;
  CalibrationSilhouettes? _silhouettes;

  String _guidance = '화면 안으로 들어와 주세요';
  String? _targetView = 'front';
  List<String> _capturedViews = const [];
  double _holdProgress = 0;
  bool _isPassing = false;
  String? _error;

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
        setState(() {
          _guidance = args['guidance'] as String? ?? _guidance;
          _targetView = args['targetView'] as String?;
          _capturedViews =
              (args['capturedViews'] as List?)?.cast<String>() ?? _capturedViews;
          _holdProgress = (args['holdProgress'] as num?)?.toDouble() ?? 0;
          _isPassing = args['isPassing'] as bool? ?? false;
        });
        if (args['isFinished'] == true && sessionPath != null) {
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
            _HelpTip('몸에 붙는 옷이면 더 정확해'),
            SizedBox(height: 10),
            _HelpTip('휴대폰을 세워서 고정하고 2m 정도 떨어져 줘'),
            SizedBox(height: 10),
            _HelpTip('팔은 A자로 벌리고, 제자리에서 천천히 한 바퀴 돌면 돼'),
            SizedBox(height: 10),
            _HelpTip('뒤를 볼 땐 화면이 안 보이니까 소리를 들어줘'),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _channel?.invokeMethod<void>('cancel');
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _capturedViews.length.clamp(0, _views.length - 1);
    final label = _viewLabels[_targetView] ?? _viewLabels[_views[currentIndex]]!;

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
            _isIOS
                ? UiKitView(
                    viewType: OnboardingScanScreen.viewType,
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: _onPlatformViewCreated,
                  )
                : Container(color: AppColors.grey),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '닫기',
                          onPressed: _cancel,
                          icon: const Icon(Icons.close_rounded,
                              color: AppColors.white, size: 24),
                        ),
                        Expanded(
                          child: Text(
                            '${_capturedViews.length} / ${_views.length} · $label',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        GestureDetector(
                          onTap: _showHelp,
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
                        for (var i = 0; i < _views.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: _capturedViews.contains(_views[i]) ? 1 : 0,
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
                            child: _silhouettes == null
                                ? const SizedBox.shrink()
                                : CustomPaint(
                                    size: Size.infinite,
                                    painter: CalibrationSilhouettePainter(
                                      silhouettes: _silhouettes!,
                                      view: _targetView,
                                      isPassing: _isPassing,
                                      progress: _holdProgress,
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
                      message: _error == null ? _guidance : _errorMessage(_error!),
                      holdProgress: _holdProgress,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        for (var i = 0; i < _views.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _PoseChip(
                              label: _viewLabels[_views[i]]!,
                              state: _capturedViews.contains(_views[i])
                                  ? _ChipState.done
                                  : _views[i] == _targetView
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

  String _errorMessage(String error) => switch (error) {
        'camera_permission_denied' => '설정에서 카메라 권한을 켜줘',
        _ => '카메라를 시작하지 못했어. 다시 시도해줘',
      };
}

class _StatusBubble extends StatelessWidget {
  const _StatusBubble({required this.message, required this.holdProgress});

  final String message;
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
            child: Text(
              message,
              style: const TextStyle(
                  color: AppColors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  height: 1.4),
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
