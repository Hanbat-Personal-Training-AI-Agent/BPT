import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../constants/route_constants.dart';
import '../theme/app_colors.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    RouteConstants.home,
    RouteConstants.calendar,
    RouteConstants.report,
    RouteConstants.profile,
  ];

  static const _workoutRoutes = [
    RouteConstants.exerciseSelection,
    RouteConstants.nativePoseWorkout,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 운동 탭도 go()로 이동해야 다른 4개 탭과 동일하게 GoRouterState가 즉시
    // 갱신된다. (push()는 ShellRoute의 내부 Navigator 안에서만 쌓여서
    // 네비바가 현재 위치 변화를 못 읽는 문제가 있었다.)
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _tabs.indexWhere((t) => location.startsWith(t));
    final workoutActive = _workoutRoutes.any((r) => location.startsWith(r));

    return Scaffold(
      backgroundColor: AppColors.black,
      extendBody: true,
      // 각 탭 화면이 자기만의 Scaffold를 갖고 있어서(중첩 Scaffold), 여기서도
      // 리사이즈하면 키보드가 뜰 때 인셋이 이중으로 적용돼 입력칸이 필요 이상으로
      // 밀려 올라간다. 실제 키보드 인셋 대응은 각 화면의 안쪽 Scaffold가 맡는다.
      resizeToAvoidBottomInset: false,
      body: child,
      bottomNavigationBar: _BPTNavBar(
        currentIndex: currentIndex,
        workoutActive: workoutActive,
        onTabTap: (i) => context.go(_tabs[i]),
        onWorkoutTap: () => context.go(RouteConstants.exerciseSelection),
      ),
    );
  }
}

/// 화면 하단에 떠 있는 캡슐형 네비게이션 바.
/// 홈/캘린더/리포트/프로필은 현재 라우트에 따라 활성/비활성 스타일이 바뀌고,
/// 가운데 운동 버튼은 항상 초록색으로 떠 있는 플로팅 액션 버튼이다.
class _BPTNavBar extends StatefulWidget {
  const _BPTNavBar({
    required this.currentIndex,
    required this.workoutActive,
    required this.onTabTap,
    required this.onWorkoutTap,
  });

  final int currentIndex;
  final bool workoutActive;
  final ValueChanged<int> onTabTap;
  final VoidCallback onWorkoutTap;

  @override
  State<_BPTNavBar> createState() => _BPTNavBarState();
}

class _BPTNavBarState extends State<_BPTNavBar> {
  static const double _barWidth = 360;
  static const double _barHeight = 72;
  static const double _fabSize = 48;
  static const double _indicatorSize = 44;

  /// 탭 4개가 놓인 칸 위치 (가운데 2번 칸은 운동 버튼 자리).
  static const _tabSlots = [0, 1, 3, 4];
  static const _slotCount = 5;

  /// 화면 전환 슬라이드와 같은 속도로 움직여서 함께 넘어가는 것처럼 보이게 한다.
  static const _slideDuration = Duration(milliseconds: 320);

  // 운동 화면에 있을 때(선택된 탭 없음)는 마지막 위치에서 흐려지기만 한다.
  int _lastSlot = 0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final currentIndex = widget.currentIndex;
    final hasTab = currentIndex >= 0 && currentIndex < _tabSlots.length;
    if (hasTab) _lastSlot = _tabSlots[currentIndex];

    return Padding(
      padding:
          EdgeInsets.fromLTRB(0, 0, 0, bottomInset > 0 ? bottomInset - 8 : 16),
      child: Center(
        heightFactor: 1,
        child: SizedBox(
          width: _barWidth,
          height: _barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: _barWidth,
                height: _barHeight,
                decoration: BoxDecoration(
                  color: AppColors.grey,
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                  border: Border.all(color: const Color(0xFF5C5C5C), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final slotWidth = constraints.maxWidth / _slotCount;
                    return Stack(
                      children: [
                        // 선택 표시 원: 탭을 바꾸면 옆으로 미끄러져 이동한다.
                        AnimatedPositioned(
                          duration: _slideDuration,
                          curve: Curves.easeOutCubic,
                          left: slotWidth * (_lastSlot + 0.5) -
                              _indicatorSize / 2,
                          top: (constraints.maxHeight - _indicatorSize) / 2,
                          width: _indicatorSize,
                          height: _indicatorSize,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: hasTab ? 1 : 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                        ),
                        _buildIconRow(),
                      ],
                    );
                  },
                ),
              ),
              _WorkoutFab(
                size: _fabSize,
                active: widget.workoutActive,
                onTap: widget.onWorkoutTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconRow() {
    final currentIndex = widget.currentIndex;
    final onTabTap = widget.onTabTap;
    return Row(
      children: [
        _NavIcon(
          assetPath: 'assets/icons/nav/home.svg',
          iconSize: 24,
          selected: currentIndex == 0,
          onTap: () => onTabTap(0),
        ),
        _NavIcon(
          assetPath: 'assets/icons/nav/calendar.svg',
          iconSize: 20,
          selected: currentIndex == 1,
          onTap: () => onTabTap(1),
        ),
        const Expanded(child: SizedBox()),
        _NavIcon(
          assetPath: 'assets/icons/nav/report.svg',
          iconSize: 28,
          selected: currentIndex == 2,
          onTap: () => onTabTap(2),
        ),
        _NavIcon(
          assetPath: 'assets/icons/nav/profile.svg',
          iconSize: 20,
          selected: currentIndex == 3,
          onTap: () => onTabTap(3),
        ),
      ],
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.assetPath,
    required this.iconSize,
    required this.selected,
    required this.onTap,
  });

  final String assetPath;
  final double iconSize;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          // 배경 원은 네비바가 따로 슬라이드시키고, 아이콘은 색만 부드럽게 바뀐다.
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: selected
                  ? AppColors.green
                  : Colors.white.withValues(alpha: 0.35),
            ),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, color, _) => SvgPicture.asset(
              assetPath,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(color!, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}

/// 항상 초록색으로 떠 있는 운동 시작 버튼. 누르고 있거나 운동 관련 화면(운동
/// 선택/진행)에 있을 때 글로우가 표시된다.
class _WorkoutFab extends StatefulWidget {
  const _WorkoutFab({
    required this.size,
    required this.active,
    required this.onTap,
  });

  final double size;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_WorkoutFab> createState() => _WorkoutFabState();
}

class _WorkoutFabState extends State<_WorkoutFab> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  static final Color _haloColor = HSLColor.fromColor(AppColors.green)
      .withLightness(0.28)
      .toColor()
      .withValues(alpha: 0.45);

  @override
  Widget build(BuildContext context) {
    final glowing = _pressed || widget.active;
    final haloSize = widget.size + 11;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: haloSize,
        height: haloSize,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: glowing ? haloSize : widget.size,
              height: glowing ? haloSize : widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: glowing ? _haloColor : Colors.transparent,
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.green,
              ),
              child: SvgPicture.asset(
                'assets/icons/nav/workout.svg',
                width: 28,
                height: 28,
                colorFilter:
                    const ColorFilter.mode(AppColors.black, BlendMode.srcIn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
