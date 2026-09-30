import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum AppToastType { info, error }

/// 하단 네비게이션 바 위에 뜨는 둥근 사각형 토스트.
/// 아래에서 위로 올라왔다가 잠시 뒤 다시 아래로 내려가며 사라진다.
///
/// 루트 Overlay 에 붙이므로, 호출 직후 `context.go()` 로 화면을 바꿔도
/// 새 화면 위에 그대로 보인다.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastType type = AppToastType.info,
  Duration duration = const Duration(milliseconds: 2200),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  // 토스트는 한 번에 하나만 보여준다.
  _current?.remove();
  _current = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AppToast(
      message: message,
      type: type,
      duration: duration,
      onDismissed: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

OverlayEntry? _current;

class _AppToast extends StatefulWidget {
  const _AppToast({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final AppToastType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  // MainShell 의 캡슐 네비게이션 바 높이/하단 여백과 맞춘 값.
  static const double _navBarHeight = 72;
  static const double _gapAboveNav = 12;
  // 네비게이션 바와 같은 너비. 좁은 화면에서는 양옆 여백을 남긴다.
  static const double _maxWidth = 360;
  static const double _sideMargin = 16;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  ));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _ctrl.forward();
    await Future<void>.delayed(widget.duration);
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final navBottom = bottomInset > 0 ? bottomInset - 8 : 16.0;
    final isError = widget.type == AppToastType.error;
    // 잘 보이도록 분홍 배경 + 검은 글씨. 오류는 빨간 배경.
    final background = isError ? AppColors.red : AppColors.pink;
    final width = math.min(
        _maxWidth, MediaQuery.of(context).size.width - _sideMargin * 2);

    return Positioned(
      left: 0,
      right: 0,
      bottom: navBottom + _navBarHeight + _gapAboveNav,
      child: IgnorePointer(
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Center(
              child: SizedBox(
                width: width,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 16, 18, 16),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: AppColors.black,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isError
                                ? Icons.priority_high_rounded
                                : Icons.info_outline_rounded,
                            size: 17,
                            color: background,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
