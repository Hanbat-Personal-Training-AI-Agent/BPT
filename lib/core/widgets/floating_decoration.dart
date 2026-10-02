import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 장식 이미지(반짝이, 하트 등)를 은은하게 둥실둥실 움직이는 래퍼.
///
/// 위아래로 살짝 떠다니면서 조금씩 기울고 커졌다 작아진다. 사인파 하나로
/// 세 움직임을 같이 돌려서 끊김 없이 반복된다. 여러 장식이 같은 박자로
/// 움직이지 않도록 [period]와 [phase]를 장식마다 다르게 주면 된다.
/// 기기에서 '동작 줄이기'가 켜져 있으면 움직이지 않는다.
class FloatingDecoration extends StatefulWidget {
  const FloatingDecoration({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 2800),
    this.phase = 0,
    this.floatDistance = 4,
    this.rotationDegrees = 6,
    this.scaleAmount = 0.05,
  });

  final Widget child;

  /// 한 번 오르내리는 데 걸리는 시간.
  final Duration period;

  /// 시작 위치(0~1). 장식끼리 박자를 엇갈리게 할 때 쓴다.
  final double phase;

  /// 위아래로 움직이는 거리(px).
  final double floatDistance;

  /// 좌우로 기우는 최대 각도.
  final double rotationDegrees;

  /// 커졌다 작아지는 비율 (0.05 = ±5%).
  final double scaleAmount;

  @override
  State<FloatingDecoration> createState() => _FloatingDecorationState();
}

class _FloatingDecorationState extends State<FloatingDecoration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        child: widget.child,
        builder: (context, child) {
          final t = 2 * math.pi * (_ctrl.value + widget.phase);
          final wave = math.sin(t);
          // 기울기와 크기는 위치보다 박자를 살짝 늦춰서 더 말랑하게 보이게 한다.
          final lagged = math.sin(t - math.pi / 3);
          return Transform.translate(
            offset: Offset(0, -wave * widget.floatDistance),
            child: Transform.rotate(
              angle: lagged * widget.rotationDegrees * math.pi / 180,
              child: Transform.scale(
                scale: 1 + lagged * widget.scaleAmount,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
