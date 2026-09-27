import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';

/// Placeholder shell for the "체형 측정 결과 (3D)" screen shown after
/// analysis finishes. The skeleton is a flat 2D drawing faked into looking
/// 3D by applying a perspective Y-rotation as the user drags — there's no
/// real 3D model or backend result wired up yet.
class OnboardingResultScreen extends StatefulWidget {
  const OnboardingResultScreen({super.key});

  @override
  State<OnboardingResultScreen> createState() =>
      _OnboardingResultScreenState();
}

class _OnboardingResultScreenState extends State<OnboardingResultScreen> {
  double _angle = 0;

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
                      const Text('측정 끝!',
                          style: TextStyle(
                              color: AppColors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('공유 기능은 아직 준비 중이야.')),
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
                        Center(
                          child: GestureDetector(
                            onHorizontalDragUpdate: (details) => setState(
                                () => _angle += details.delta.dx * 0.012),
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0009)
                                ..rotateY(_angle),
                              child: SizedBox(
                                width: 180,
                                height: 320,
                                child: CustomPaint(
                                  painter: _ResultSkeletonPainter(),
                                ),
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
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                      const Expanded(
                        child: Text('이 체형 정보로 앞으로 자세를\n더 정확하게 봐줄게!',
                            style: TextStyle(
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

/// Flat stick-figure body outline, drawn once and then faked into 3D by
/// the caller's [Transform] + drag handling.
class _ResultSkeletonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    Offset p(double fx, double fy) => Offset(fx * w, fy * h);

    final headCenter = p(0.5, 0.12);
    final headRadius = h * 0.07;
    final neck = Offset(headCenter.dx, headCenter.dy + headRadius);
    final leftShoulder = p(0.28, 0.28);
    final rightShoulder = p(0.72, 0.28);
    final leftHip = p(0.34, 0.55);
    final rightHip = p(0.66, 0.55);
    final leftKnee = p(0.32, 0.76);
    final rightKnee = p(0.68, 0.76);
    final leftAnkle = p(0.30, 0.98);
    final rightAnkle = p(0.70, 0.98);
    final hipCenter = Offset(
        (leftHip.dx + rightHip.dx) / 2, (leftHip.dy + rightHip.dy) / 2);

    final line = Paint()
      ..color = AppColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(headCenter, headRadius, line);
    canvas.drawLine(neck, hipCenter, line);
    canvas.drawLine(leftShoulder, rightShoulder, line);
    canvas.drawLine(leftShoulder, leftHip, line);
    canvas.drawLine(rightShoulder, rightHip, line);
    canvas.drawLine(leftHip, rightHip, line);
    canvas.drawLine(leftHip, leftKnee, line);
    canvas.drawLine(leftKnee, leftAnkle, line);
    canvas.drawLine(rightHip, rightKnee, line);
    canvas.drawLine(rightKnee, rightAnkle, line);

    final joint = Paint()..color = AppColors.white;
    for (final j in [
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
      leftKnee,
      rightKnee,
    ]) {
      canvas.drawCircle(j, 5, joint);
    }

    final glow = Paint()
      ..color = AppColors.green.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w / 2, h * 0.985), width: w * 0.6, height: h * 0.03),
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant _ResultSkeletonPainter oldDelegate) => false;
}
