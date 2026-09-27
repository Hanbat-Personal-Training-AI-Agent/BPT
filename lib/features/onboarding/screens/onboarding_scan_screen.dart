import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';

enum _CapturePose { front, left, back, right }

/// Full-screen native camera capture step: shown after the user taps
/// "카메라 켜기" on [OnboardingCaptureScreen]. Hosts the native
/// `bpt/body_scan_camera` PlatformView (live camera + RTMPose skeleton +
/// stillness auto-capture) and drives the countdown UI from its
/// `onScanUpdate` channel events.
class OnboardingScanScreen extends StatefulWidget {
  const OnboardingScanScreen({super.key});

  static const String viewType = 'bpt/body_scan_camera';

  @override
  State<OnboardingScanScreen> createState() => _OnboardingScanScreenState();
}

class _OnboardingScanScreenState extends State<OnboardingScanScreen> {
  static const _poses = _CapturePose.values;
  static const _poseLabels = {
    _CapturePose.front: '정면',
    _CapturePose.left: '왼쪽',
    _CapturePose.back: '뒷면',
    _CapturePose.right: '오른쪽',
  };
  static const _poseHints = {
    _CapturePose.front: '카메라 보고 팔은 A자로,\n발은 어깨너비로 벌려 줘!',
    _CapturePose.left: '제자리에서 왼쪽으로 비스듬히 돌아 줘.\n고개도 몸이랑 같은 방향으로!',
    _CapturePose.back: '이번엔 등을 보여 줘.\n팔은 계속 A자 유지!',
    _CapturePose.right: '마지막! 오른쪽으로 비스듬히 돌아 줘.\n거의 다 왔어!',
  };

  MethodChannel? _channel;
  int _poseIndex = 0;
  final Map<_CapturePose, String> _capturedPaths = {};
  String _status = 'searching';
  int _countdown = 0;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  _CapturePose get _pose => _poses[_poseIndex];
  bool get _allCaptured => _capturedPaths.length == _poses.length;

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('${OnboardingScanScreen.viewType}/$id');
    _channel!.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onScanUpdate') return null;
    final args = (call.arguments as Map).cast<String, dynamic>();
    final status = args['status'] as String? ?? 'searching';
    final countdown = (args['countdown'] as num?)?.toInt() ?? 0;
    final path = args['path'] as String?;

    if (!mounted) return null;

    if (status == 'captured' && path != null) {
      _onCaptured(path);
      return null;
    }

    setState(() {
      _status = status;
      _countdown = countdown;
    });
    return null;
  }

  void _onCaptured(String path) {
    setState(() {
      _capturedPaths[_pose] = path;
      _status = 'searching';
      _countdown = 0;
      if (_poseIndex < _poses.length - 1) _poseIndex += 1;
    });
    if (_allCaptured) {
      context.go(RouteConstants.onboardingAnalyzing,
          extra: _poses.map((p) => _capturedPaths[p]!).toList());
    }
  }

  // TODO(temp): debug-only skip button so the flow can be tested on the
  // simulator (no real camera). Remove once real-device testing is set up.
  void _debugSkip() => _onCaptured('');

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
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.close_rounded,
                              color: AppColors.white, size: 24),
                        ),
                        Expanded(
                          child: Text(
                            '${_poseIndex + 1} / ${_poses.length} · ${_poseLabels[_pose]}',
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
                        for (var i = 0; i < _poses.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: i <= _poseIndex ? 1 : 0,
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
                            child: CustomPaint(
                              size: Size.infinite,
                              painter:
                                  _DashedGuidePainter(color: AppColors.green),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: _StatusBubble(
                        status: _status,
                        countdown: _countdown,
                        hint: _poseHints[_pose]!),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        for (var i = 0; i < _poses.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _PoseChip(
                              label: _poseLabels[_poses[i]]!,
                              state: i < _poseIndex
                                  ? _ChipState.done
                                  : i == _poseIndex
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
            // TODO(temp): debug-only skip button — remove once real-device
            // testing is set up (the simulator has no camera to auto-advance).
            Positioned(
              right: 16,
              bottom: 100,
              child: SafeArea(
                child: GestureDetector(
                  onTap: _debugSkip,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.red, width: 1.5),
                    ),
                    child: const Text('다음 (테스트용)',
                        style: TextStyle(
                            color: AppColors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBubble extends StatelessWidget {
  const _StatusBubble(
      {required this.status, required this.countdown, required this.hint});

  final String status;
  final int countdown;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final isHolding = status == 'holding';
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
            child: isHolding
                ? RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          color: AppColors.black, height: 1.4),
                      children: [
                        TextSpan(
                          text: '좋아, 그대로 멈춰! $countdown초 뒤에 찍을게!\n',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(
                          text: '저장은 내가 알아서 할게!',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : Text(
                    hint,
                    style: const TextStyle(
                        color: AppColors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        height: 1.4),
                  ),
          ),
          if (isHolding) ...[
            const SizedBox(width: 10),
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.black,
                shape: BoxShape.circle,
              ),
              child: Text('$countdown',
                  style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
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
                color: AppColors.pink, fontSize: 12, fontWeight: FontWeight.w700)),
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
                  color: textColor, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(statusWord,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: textColor, fontSize: 12, fontWeight: FontWeight.w700)),
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

/// Dashed rounded-capsule "stand here" guide outline, drawn over the camera.
class _DashedGuidePainter extends CustomPainter {
  _DashedGuidePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width / 2),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    const dashWidth = 7.0;
    const dashGap = 6.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedGuidePainter oldDelegate) =>
      oldDelegate.color != color;
}
