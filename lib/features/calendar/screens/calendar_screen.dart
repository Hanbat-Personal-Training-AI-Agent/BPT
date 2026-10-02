import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/mock_data.dart';
import '../../../models/workout_record_model.dart';
import '../../home/providers/home_provider.dart';

const _weekdayHeaderKo = ['일', '월', '화', '수', '목', '금', '토'];
const _weekdayHeaderEn = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const _monthsKo = [
  '1월',
  '2월',
  '3월',
  '4월',
  '5월',
  '6월',
  '7월',
  '8월',
  '9월',
  '10월',
  '11월',
  '12월',
];
const _monthsEn = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// 62.5 → "62.5", 60.0 → "60"
String _formatKg(double kg) =>
    kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toString();

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _visibleMonth;
  DateTime? _selectedDate;

  /// 마지막으로 넘긴 방향. 1: 다음 달, -1: 이전 달.
  int _monthSlideDirection = 1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _selectedDate = _dateOnly(now);
  }

  void _changeMonth(int delta) {
    setState(() {
      _monthSlideDirection = delta > 0 ? 1 : -1;
      _visibleMonth =
          DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final isKo = s.locale == 'ko';
    final records = ref.watch(allRecordsProvider);

    final monthRecords = records
        .where((r) =>
            r.date.year == _visibleMonth.year &&
            r.date.month == _visibleMonth.month)
        .toList();

    final workoutDates = monthRecords.map((r) => _dateOnly(r.date)).toSet();

    final selectedDate = _selectedDate;
    final selectedRecords = selectedDate == null
        ? const <WorkoutRecordModel>[]
        : records.where((r) => _dateOnly(r.date) == selectedDate).toList();

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 고정 영역: 헤더 + 월 캘린더 카드 (스크롤에 영향받지 않음)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isKo ? '캘린더' : 'Calendar',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          isKo
                              ? '${_monthsKo[_visibleMonth.month - 1]} ${monthRecords.length}번 운동'
                              : '${monthRecords.length} workouts in ${_monthsEn[_visibleMonth.month - 1]}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _MonthCalendarCard(
                      visibleMonth: _visibleMonth,
                      slideDirection: _monthSlideDirection,
                      selectedDate: _selectedDate,
                      workoutDates: workoutDates,
                      isKo: isKo,
                      onPrevMonth: () => _changeMonth(-1),
                      onNextMonth: () => _changeMonth(1),
                      onSelectDate: (d) => setState(() => _selectedDate = d),
                    ),
                  ],
                ),
              ),
              // 스크롤 영역: 선택한 날짜의 기록만 스크롤됨
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  child: selectedDate == null
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            const SizedBox(height: 28),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  isKo
                                      ? '${selectedDate.month}월 ${selectedDate.day}일'
                                      : '${_monthsEn[selectedDate.month - 1]} ${selectedDate.day}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (selectedRecords.isNotEmpty)
                                  GestureDetector(
                                    onTap: () =>
                                        context.go(RouteConstants.report),
                                    child: Text(
                                      isKo ? '기록 보기' : 'View records',
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.4),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (selectedRecords.isEmpty)
                              _CalendarEmptyState(isKo: isKo)
                            else
                              ...selectedRecords.map((r) =>
                                  _CalendarRecordTile(record: r, isKo: isKo)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Month Calendar Card ─────────────────────────────────────────────────────
class _MonthCalendarCard extends StatelessWidget {
  const _MonthCalendarCard({
    required this.visibleMonth,
    required this.slideDirection,
    required this.selectedDate,
    required this.workoutDates,
    required this.isKo,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onSelectDate,
  });

  final DateTime visibleMonth;

  /// 1: 다음 달로 넘김, -1: 이전 달로 넘김.
  final int slideDirection;
  final DateTime? selectedDate;
  final Set<DateTime> workoutDates;
  final bool isKo;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth =
        DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday % 7;
    final monthLabel = isKo
        ? '${visibleMonth.year}년 ${_monthsKo[visibleMonth.month - 1]}'
        : '${_monthsEn[visibleMonth.month - 1]} ${visibleMonth.year}';
    final weekdayHeader = isKo ? _weekdayHeaderKo : _weekdayHeaderEn;

    // 좌우로 쓸어 넘겨도 달이 바뀐다 (왼쪽으로 쓸면 다음 달).
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) onNextMonth();
        if (v > 200) onPrevMonth();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        decoration: BoxDecoration(
          color: AppColors.grey,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MonthNavButton(
                    icon: Icons.chevron_left_rounded, onTap: onPrevMonth),
                // 월 제목: 넘기는 방향으로 살짝 밀리며 바뀐다.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final incoming = child.key == ValueKey(monthLabel);
                    final dx =
                        (incoming ? slideDirection : -slideDirection) * 0.35;
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: animation.drive(
                          Tween(begin: Offset(dx, 0), end: Offset.zero),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    monthLabel,
                    key: ValueKey(monthLabel),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _MonthNavButton(
                    icon: Icons.chevron_right_rounded, onTap: onNextMonth),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: List.generate(7, (i) {
                final Color color;
                if (i == 0) {
                  color = AppColors.red;
                } else if (i == 6) {
                  color = AppColors.purple;
                } else {
                  color = Colors.white.withValues(alpha: 0.55);
                }
                return Expanded(
                  child: Center(
                    child: Text(
                      weekdayHeader[i],
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            _MonthGridSlider(
              monthKey: ValueKey(visibleMonth),
              direction: slideDirection,
              child: GridView.builder(
                key: ValueKey(visibleMonth),
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1,
                ),
                itemCount: leadingBlanks + daysInMonth,
                itemBuilder: (context, index) {
                  if (index < leadingBlanks) return const SizedBox.shrink();
                  final day = index - leadingBlanks + 1;
                  final date =
                      DateTime(visibleMonth.year, visibleMonth.month, day);
                  final isToday = date == today;
                  final isSelected = date == selectedDate;
                  final hasWorkout = workoutDates.contains(date);

                  return GestureDetector(
                    onTap: () => onSelectDate(date),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                isToday ? AppColors.green : Colors.transparent,
                            border: (!isToday && isSelected)
                                ? Border.all(
                                    color: Colors.white.withValues(alpha: 0.4))
                                : null,
                          ),
                          child: Text(
                            '$day',
                            style: TextStyle(
                              color: isToday ? AppColors.black : Colors.white,
                              fontWeight:
                                  isToday ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          width: 5,
                          height: 5,
                          child: hasWorkout
                              ? const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.green,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 월 넘김 슬라이드 ────────────────────────────────────────────────────────
/// 날짜 칸을 넘기는 방향으로 밀어서 바꾼다. 다음 달이면 새 달이 오른쪽에서 들어오고
/// 이전 달은 왼쪽으로 밀려나며, 두 달이 붙어서 움직인다. 달마다 줄 수(5/6주)가
/// 달라 높이가 바뀌는 것도 부드럽게 맞춘다.
class _MonthGridSlider extends StatelessWidget {
  const _MonthGridSlider({
    required this.monthKey,
    required this.direction,
    required this.child,
  });
  final Key monthKey;
  final int direction;
  final Widget child;

  static const _duration = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final dir = direction.toDouble();
    return ClipRect(
      child: AnimatedSize(
        duration: _duration,
        curve: _curve,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: _duration,
          switchInCurve: _curve,
          // 나가는 달은 애니메이션이 거꾸로 돌아서 뒤집은 곡선을 써야 같이 붙어 움직인다.
          switchOutCurve: _curve.flipped,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) {
            final incoming = child.key == monthKey;
            return SlideTransition(
              position: animation.drive(Tween(
                begin: Offset(incoming ? dir : -dir, 0),
                end: Offset.zero,
              )),
              child: child,
            );
          },
          child: child,
        ),
      ),
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 22),
      ),
    );
  }
}

// ── Empty state for a selected day with no records ─────────────────────────
class _CalendarEmptyState extends StatelessWidget {
  const _CalendarEmptyState({required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Image.asset(
            'assets/images/character/considering.png',
            width: 120,
            height: 120,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 10),
          Text(
            isKo ? '이 날은 기록이 없어!' : 'No records on this day!',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Record tile for the selected day ────────────────────────────────────────
class _CalendarRecordTile extends StatelessWidget {
  const _CalendarRecordTile({required this.record, required this.isKo});
  final WorkoutRecordModel record;
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    final ex = findExercise(record.exerciseId);
    final weight = record.weightKg > 0
        ? record.weightKg
        : mockWeightKgByExercise[record.exerciseId]?.toDouble();

    return GestureDetector(
      onTap: () => context.push(
        RouteConstants.workoutResult,
        extra: {
          'exerciseId': record.exerciseId,
          'exerciseName': record.exerciseName,
          'exerciseNameKr': ex.nameKr,
          'totalReps': record.totalReps,
          'correctReps': record.correctReps,
          'incorrectReps': record.incorrectReps,
          'elapsedSeconds': record.durationSeconds,
          'postureScore': record.postureScore,
          'feedbackHistory': record.feedbackNotes,
          'targetReps': record.targetReps,
          'targetSets': record.targetSets,
          'weightKg': record.weightKg,
          'isHistory': true,
          'date': record.date,
        },
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.grey,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    'assets/icons/nav/workout.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                        AppColors.black, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isKo ? ex.nameKr : record.exerciseName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (weight != null && weight > 0) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.purple,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_formatKg(weight)}kg',
                      style: const TextStyle(
                        color: AppColors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.3), size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 10),
            Text(
              isKo
                  ? '${record.targetSets}세트 × ${record.repsPerSet}회'
                  : '${record.targetSets} sets × ${record.repsPerSet} reps',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
