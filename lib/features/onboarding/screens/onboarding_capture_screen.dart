import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/onboarding_scaffold.dart';

enum _CapturePose { front, left, right }

class OnboardingCaptureScreen extends StatefulWidget {
  const OnboardingCaptureScreen({super.key});

  @override
  State<OnboardingCaptureScreen> createState() =>
      _OnboardingCaptureScreenState();
}

class _OnboardingCaptureScreenState extends State<OnboardingCaptureScreen> {
  _CapturePose _pose = _CapturePose.front;

  String get _poseImage => switch (_pose) {
        _CapturePose.front => 'assets/images/character/front.png',
        _CapturePose.left => 'assets/images/character/left.png',
        _CapturePose.right => 'assets/images/character/right.png',
      };

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 4,
      totalSteps: 4,
      onBack: () => context.pop(),
      nextLabel: '카메라 켜기',
      onNext: () => context.push(RouteConstants.onboardingScan),
      headline: const Text('마지막이야!\n네 방향만 찍으면 끝이야',
          style: TextStyle(
              fontSize: 27,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -1)),
      body: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Image.asset(
              'assets/images/character/face.png',
              width: 62,
              height: 68,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppColors.purple,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
                    bottomRight: Radius.circular(22),
                    bottomLeft: Radius.circular(3),
                  ),
                ),
                child: const Text(
                  '버튼은 안 눌러도 돼.\n가이드에 맞춰 서 있으면\n내가 알아서 찍을게!',
                  style: TextStyle(
                      color: AppColors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.4),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _PoseStep(
                number: 1,
                label: '정면',
                selected: _pose == _CapturePose.front,
                onTap: () => setState(() => _pose = _CapturePose.front),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PoseStep(
                number: 2,
                label: '왼쪽 측면',
                selected: _pose == _CapturePose.left,
                onTap: () => setState(() => _pose = _CapturePose.left),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PoseStep(
                number: 3,
                label: '오른쪽 측면',
                selected: _pose == _CapturePose.right,
                onTap: () => setState(() => _pose = _CapturePose.right),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.grey,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: SizedBox(
              width: 140,
              height: 170,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    size: const Size(140, 170),
                    painter: _DashedGuidePainter(color: AppColors.green),
                  ),
                  // OverflowBox lets the character render larger than the
                  // 140x170 guide capsule without that capsule (or anything
                  // else) changing size — a plain sized Image here was
                  // silently clamped to the capsule's own constraints.
                  OverflowBox(
                    maxWidth: 175,
                    maxHeight: 175,
                    child: Image.asset(
                      _poseImage,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.grey,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChecklistItem('몸에 붙는 옷이면 더 정확해'),
              SizedBox(height: 8),
              _ChecklistItem('2m 정도 떨어져서 전신이 한 번에 보이게 해줘'),
            ],
          ),
        ),
      ],
    );
  }
}

class _PoseStep extends StatelessWidget {
  const _PoseStep({
    required this.number,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.grey,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? AppColors.green : Colors.transparent,
                width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: selected ? AppColors.green : const Color(0xFF2B2B2B),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('$number',
                      style: TextStyle(
                          color: selected ? AppColors.black : AppColors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color:
                          selected ? AppColors.white : const Color(0xFF888888),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem(this.text);
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

/// Dashed rounded-rectangle "stand here" guide outline.
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
      ..strokeWidth = 2;

    const dashWidth = 6.0;
    const dashGap = 5.0;
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
