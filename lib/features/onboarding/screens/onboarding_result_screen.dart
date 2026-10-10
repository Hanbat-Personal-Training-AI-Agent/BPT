import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';

/// "체형 측정 결과 (3D)": the server's real body fit (GET calibrations/jobs
/// `done` result). The skeleton is the result's rest-pose H36M joints in 3D,
/// rotated about the vertical axis as the user drags — not a flat drawing.
/// Without a result nothing is drawn: no demo body.
class OnboardingResultScreen extends StatefulWidget {
  const OnboardingResultScreen({super.key, this.result});

  /// The `result` object of a `done` calibration job.
  final Map<String, dynamic>? result;

  @override
  State<OnboardingResultScreen> createState() => _OnboardingResultScreenState();
}

class _OnboardingResultScreenState extends State<OnboardingResultScreen> {
  double _angle = 0;

  @override
  Widget build(BuildContext context) {
    final joints = BodyJoints.fromResult(widget.result);
    final comment = widget.result?['coachComment'];
    return Theme(
      data: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Pretendard'),
        scaffoldBackgroundColor: AppColors.black,
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(joints == null ? '체형 결과 없음' : '측정 끝!',
                          style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('공유 기능은 아직 준비 중이야.')),
                          ),
                          child: const Text('공유',
                              style: TextStyle(
                                  color: AppColors.green,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.grey,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Stack(
                      children: [
                        const Align(
                          alignment: Alignment.topLeft,
                          child: Text('3D BODY MODEL',
                              style: TextStyle(
                                  color: Color(0xFF5A5A5A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                        ),
                        if (joints == null)
                          const Center(
                            child: Text(
                              '아직 분석 결과가 없어요.\n사진 4장을 전송하고 분석이 끝나면 볼 수 있어요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(height: 1.5),
                            ),
                          )
                        else ...[
                          Center(
                            child: GestureDetector(
                              key: const Key('body-3d'),
                              onHorizontalDragUpdate: (details) => setState(
                                  () => _angle += details.delta.dx * 0.012),
                              child: SizedBox(
                                width: 220,
                                height: 340,
                                child: CustomPaint(
                                  painter: BodySkeletonPainter(joints, _angle),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        color: AppColors.white, size: 16),
                                    SizedBox(width: 6),
                                    Text('드래그해서 360° 돌려봐',
                                        style: TextStyle(
                                            color: AppColors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (joints != null) ...[
                  const Row(
                    children: [
                      Expanded(child: _DoneChip(label: '정면')),
                      SizedBox(width: 10),
                      Expanded(child: _DoneChip(label: '왼쪽')),
                      SizedBox(width: 10),
                      Expanded(child: _DoneChip(label: '뒷면')),
                      SizedBox(width: 10),
                      Expanded(child: _DoneChip(label: '오른쪽')),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                      Expanded(
                        child: Text(
                            comment is String && comment.isNotEmpty
                                ? comment
                                : joints == null
                                    ? '체형을 측정하면 자세를\n더 정확하게 봐줄게!'
                                    : '이 체형 정보로 앞으로 자세를\n더 정확하게 봐줄게!',
                            style: const TextStyle(
                                color: AppColors.black,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                height: 1.35)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go(RouteConstants.home),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: AppColors.black,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('홈으로 가기',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneChip extends StatelessWidget {
  const _DoneChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.grey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF9AA0A6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            const Text('완료',
                style: TextStyle(
                    color: AppColors.green,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

/// The result's `jointsH36m`: 17 rest-pose joints in metres, SMPL axes
/// (x = the person's left, y = up, z = forward).
class BodyJoints {
  BodyJoints(this.positions);
  final List<List<double>> positions;

  /// H36M parents (server body.H36M_PARENTS): pelvis is the root.
  static const parents = [
    -1,
    0,
    1,
    2,
    0,
    4,
    5,
    0,
    7,
    8,
    9,
    8,
    11,
    12,
    8,
    14,
    15
  ];
  static const head = 10;

  static BodyJoints? fromResult(Map<String, dynamic>? result) {
    final joints = result?['jointsH36m'];
    final positions = joints is Map ? joints['positions'] : null;
    if (result?['stub'] != false ||
        positions is! List ||
        positions.length != 17 ||
        positions.any((p) =>
            p is! List ||
            p.length != 3 ||
            p.any((v) => v is! num || !v.isFinite))) {
      return null;
    }
    return BodyJoints([
      for (final p in positions)
        [for (final v in p as List) (v as num).toDouble()]
    ]);
  }

  /// Screen points after turning the body by [angle] about the vertical axis,
  /// fitted into [size] with the same scale at every angle (height fills 90%).
  List<Offset> project(double angle, Size size) {
    final ys = positions.map((p) => p[1]);
    final top = ys.reduce(math.max), bottom = ys.reduce(math.min);
    // The head joint sits below the crown; leave room for the head circle.
    final scale = size.height * 0.8 / (top - bottom);
    final c = math.cos(angle), s = math.sin(angle);
    return [
      for (final p in positions)
        Offset(size.width / 2 + (p[0] * c + p[2] * s) * scale,
            size.height * 0.92 - (p[1] - bottom) * scale)
    ];
  }
}

class BodySkeletonPainter extends CustomPainter {
  BodySkeletonPainter(this.joints, this.angle);
  final BodyJoints joints;
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final points = joints.project(angle, size);
    final line = Paint()
      ..color = AppColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < points.length; i++) {
      canvas.drawLine(points[BodyJoints.parents[i]], points[i], line);
    }
    canvas.drawCircle(points[BodyJoints.head], size.height * 0.05, line);
    final joint = Paint()..color = AppColors.white;
    for (final p in points) {
      canvas.drawCircle(p, 4, joint);
    }
  }

  @override
  bool shouldRepaint(covariant BodySkeletonPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.joints != joints;
}
