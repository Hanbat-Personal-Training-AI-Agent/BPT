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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _tabs.indexWhere((t) => location.startsWith(t));
    final currentIndex = index < 0 ? 0 : index;

    return Scaffold(
      backgroundColor: AppColors.black,
      extendBody: true,
      body: child,
      bottomNavigationBar: _BPTNavBar(
        currentIndex: currentIndex,
        onTabTap: (i) => context.go(_tabs[i]),
        onWorkoutTap: () => context.push(RouteConstants.exerciseSelection),
      ),
    );
  }
}

/// 화면 하단에 떠 있는 캡슐형 네비게이션 바.
/// 홈/캘린더/리포트/프로필은 현재 라우트에 따라 활성/비활성 스타일이 바뀌고,
/// 가운데 운동 버튼은 항상 초록색으로 떠 있는 플로팅 액션 버튼이다.
class _BPTNavBar extends StatelessWidget {
  const _BPTNavBar({
    required this.currentIndex,
    required this.onTabTap,
    required this.onWorkoutTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTabTap;
  final VoidCallback onWorkoutTap;

  static const double _barWidth = 360;
  static const double _barHeight = 72;
  static const double _fabSize = 48;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomInset > 0 ? bottomInset - 8 : 16),
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
                child: Row(
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
                ),
              ),
              _WorkoutFab(size: _fabSize, onTap: onWorkoutTap),
            ],
          ),
        ),
      ),
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
            ),
            child: Center(
              child: SvgPicture.asset(
                assetPath,
                width: iconSize,
                height: iconSize,
                colorFilter: ColorFilter.mode(
                  selected ? AppColors.green : Colors.white.withValues(alpha: 0.35),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 항상 초록색으로 떠 있는 운동 시작 버튼. 라우트 선택 상태와 무관하다.
class _WorkoutFab extends StatelessWidget {
  const _WorkoutFab({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.green,
          boxShadow: [
            BoxShadow(
              color: AppColors.green.withValues(alpha: 0.55),
              blurRadius: 20,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: AppColors.green.withValues(alpha: 0.3),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: SvgPicture.asset(
          'assets/icons/nav/workout.svg',
          width: 28,
          height: 28,
          colorFilter: const ColorFilter.mode(AppColors.black, BlendMode.srcIn),
        ),
      ),
    );
  }
}
