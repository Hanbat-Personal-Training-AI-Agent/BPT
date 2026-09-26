import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';

/// Shown right after the 3 body-scan photos are captured. Plays a fake
/// analysis progress animation (no backend call yet — the real pipeline
/// isn't wired up), then deletes the local scan photos and continues to
/// the 3D result screen.
class OnboardingAnalyzingScreen extends StatefulWidget {
  const OnboardingAnalyzingScreen({super.key, this.sessionPath});

  /// `Documents/calibration/<sessionId>` written by the native calibration session.
  final String? sessionPath;

  @override
  State<OnboardingAnalyzingScreen> createState() =>
      _OnboardingAnalyzingScreenState();
}

class _OnboardingAnalyzingScreenState extends State<OnboardingAnalyzingScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(seconds: 40);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      })
      ..forward();
  }

  void _finish() {
    // The capture bundle stays on disk: nothing uploads it yet, and the SMPL fitting
    // pipeline is fed by hand from Files/Finder. Delete it here once upload exists.
    if (mounted) context.go(RouteConstants.onboardingResult);
  }

  @override
  void dispose() {
    _controller.dispose();
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
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = _controller.value;
              final percent = (progress * 100).floor().clamp(0, 100);
              final keypointsDone = progress >= 0.5;
              final modelDone = progress >= 1.0;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: CustomPaint(
                        painter: _ProgressRingPainter(progress: progress),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$percent',
                                      style: const TextStyle(
                                          color: AppColors.white,
                                          fontSize: 44,
                                          fontWeight: FontWeight.w900),
                                    ),
                                    const TextSpan(
                                      text: '%',
                                      style: TextStyle(
                                          color: AppColors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text('분석 중',
                                  style: TextStyle(
                                      color: Color(0xFF9AA0A6),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 1),
                    const Text('체형 분석 중이야!\n금방 끝나',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.white,
                            fontSize: 24,
                            height: 1.25,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.purple,
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
                          const Expanded(
                            child: Text('40초 정도 걸려.\n조금만 기다려줘!',
                                style: TextStyle(
                                    color: AppColors.black,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    height: 1.35)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _StepRow(
                      label: '자동 촬영 3장 수집',
                      state: _StepState.done,
                    ),
                    const SizedBox(height: 10),
                    _StepRow(
                      label: '관절 키포인트 추출',
                      state: keypointsDone ? _StepState.done : _StepState.active,
                    ),
                    const SizedBox(height: 10),
                    _StepRow(
                      label: '3D 체형 만들기',
                      state: modelDone
                          ? _StepState.done
                          : keypointsDone
                              ? _StepState.active
                              : _StepState.waiting,
                    ),
                    const Spacer(flex: 1),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('사진은 분석 끝나면 바로 지울게',
                          style: TextStyle(
                              color: Color(0xFF6B6B6B),
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _StepState { done, active, waiting }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final isActive = state == _StepState.active;
    final isDone = state == _StepState.done;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isActive ? AppColors.green : Colors.transparent,
            width: 1.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: isDone
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                        color: AppColors.green, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded,
                        color: AppColors.black, size: 15),
                  )
                : isActive
                    ? const CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.green),
                      )
                    : const DecoratedBox(
                        decoration: BoxDecoration(
                            color: Color(0xFF2B2B2B), shape: BoxShape.circle),
                      ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: isActive || isDone
                        ? AppColors.white
                        : const Color(0xFF6B6B6B),
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          Text(
            isDone ? '완료' : (isActive ? '진행 중' : '대기 중'),
            style: TextStyle(
                color: isDone
                    ? const Color(0xFF9AA0A6)
                    : isActive
                        ? AppColors.green
                        : const Color(0xFF6B6B6B),
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Circular progress ring with a dark-to-bright green sweep, matching the
/// analyzing screen mockup.
class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({required this.progress});
  final double progress;

  static const _strokeWidth = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = const Color(0xFF262626)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: const [Color(0xFF4E6B1F), AppColors.green],
        stops: [0, progress.clamp(0.001, 1.0)],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);

    canvas.drawArc(rect, -math.pi / 2, progress * 2 * math.pi, false, sweep);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
