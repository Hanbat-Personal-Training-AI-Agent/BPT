import 'dart:math' as math;

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
import '../providers/home_provider.dart';

const _weekdayLabelsKo = ['월', '화', '수', '목', '금', '토', '일'];
const _weekdayLabelsEn = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final user = ref.watch(currentUserProvider);
    final summary = ref.watch(todaySummaryProvider);
    final recent = ref.watch(recentRecordsProvider);

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 고정 영역: 헤더는 스크롤에 영향받지 않음
              _BPTAppBar(name: user.name, strings: s),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  child: Column(
                    children: [
                      _StartWorkoutCard(strings: s),
                      const SizedBox(height: 16),
                      _QuickStatsRow(summary: summary, strings: s),
                      const SizedBox(height: 20),
                      _WeeklyGoalCard(strings: s),
                      const SizedBox(height: 16),
                      _BodyCheckBanner(strings: s),
                      const SizedBox(height: 28),
                      _SectionHeader(
                        title: s.recentWorkouts,
                        trailing: recent.isEmpty ? null : s.seeAll,
                        onTrailingTap: recent.isEmpty
                            ? null
                            : () => context.go(RouteConstants.report),
                      ),
                      const SizedBox(height: 12),
                      ...recent
                          .map((r) => _RecentRecordTile(record: r, strings: s)),
                      if (recent.isNotEmpty) const SizedBox(height: 12),
                      _KoriCommentCard(recent: recent, strings: s),
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

// ── App Bar ────────────────────────────────────────────────────────────────
class _BPTAppBar extends StatelessWidget {
  const _BPTAppBar({required this.name, required this.strings});
  final String name;
  final dynamic strings;

  static const _monthsEn = [
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

  String _dateLabel(bool isKo) {
    final now = DateTime.now();
    if (isKo) {
      final day = _weekdayLabelsKo[now.weekday - 1];
      return '${now.month}월 ${now.day}일 $day요일';
    }
    return '${_monthsEn[now.month - 1]} ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final isKo = strings.locale == 'ko';
    return Container(
      height: 84,
      color: AppColors.black,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _dateLabel(isKo),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isKo
                    ? '어서 와, ${name.split(' ').first}!'
                    : 'Welcome, ${name.split(' ').first}!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(
              color: AppColors.purple,
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/images/character/face.png',
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Start Workout Card (green CTA) ──────────────────────────────────────────
class _StartWorkoutCard extends StatelessWidget {
  const _StartWorkoutCard({required this.strings});
  final dynamic strings;

  static const double _cardHeight = 108;
  static const double _characterSize = 170;

  @override
  Widget build(BuildContext context) {
    final isKo = strings.locale == 'ko';
    return GestureDetector(
      onTap: () => context.push(RouteConstants.exerciseSelection),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: _cardHeight,
          color: AppColors.green,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 28,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isKo ? '오늘은 무슨 운동을 할래?' : 'What will you train today?',
                        style: TextStyle(
                          color: AppColors.black.withValues(alpha: 0.65),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isKo ? '바로 시작해보자!' : "Let's start now!",
                        style: const TextStyle(
                          color: AppColors.black,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 14,
                top: 8,
                child: Image.asset(
                  'assets/images/character/workingout.png',
                  width: _characterSize,
                  height: _characterSize,
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                ),
              ),
              Positioned(
                right: 35,
                top: 19,
                child: Image.asset(
                  'assets/images/decoration/tilde_purple.png',
                  width: 25,
                  height: 25,
                ),
              ),
              Positioned(
                right: 17,
                top: 8,
                child: Transform.rotate(
                  angle: -30 * math.pi / 180,
                  child: Image.asset(
                    'assets/images/decoration/note_purple.png',
                    width: 24,
                    height: 24,
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

// ── Quick Stats Row (운동 시간 / 완료 세트 / 총 반복) ──────────────────────
class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({required this.summary, required this.strings});
  final Map<String, dynamic> summary;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final isKo = strings.locale == 'ko';
    return Row(
      children: [
        Expanded(
          child: _StatBox(
            label: isKo ? '운동 시간' : 'Active time',
            value: '${summary['totalMinutes'] ?? 0}',
            unit: isKo ? '분' : 'm',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatBox(
            label: isKo ? '완료 세트' : 'Sets done',
            value: '${summary['completedSets'] ?? 0}',
            unit: isKo ? '세트' : ' sets',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatBox(
            label: isKo ? '총 반복' : 'Total reps',
            value: '${summary['totalReps'] ?? 0}',
            unit: isKo ? '회' : ' reps',
          ),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.unit,
  });
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: unit,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Body Check Banner (체형 재측정 배너, 3가지 상태) ───────────────────────
enum _BodyCheckState { fresh, dueSoon, overdue }

class _BodyCheckBanner extends StatelessWidget {
  const _BodyCheckBanner({required this.strings});
  final dynamic strings;

  static const int _cycleDays = 30;
  // TODO: 실제 마지막 체형 측정일이 저장되면 그 값으로 교체할 것. 지금은 목데이터.
  static const int _daysSinceLastCheck = 30;

  @override
  Widget build(BuildContext context) {
    final isKo = strings.locale == 'ko';
    final daysUntilNext =
        (_cycleDays - _daysSinceLastCheck).clamp(0, _cycleDays);

    final _BodyCheckState state;
    if (_daysSinceLastCheck >= _cycleDays) {
      state = _BodyCheckState.overdue;
    } else if (daysUntilNext <= 3) {
      state = _BodyCheckState.dueSoon;
    } else {
      state = _BodyCheckState.fresh;
    }

    late final Color bg;
    late final Color fg;
    late final String title;
    late final String subtitle;

    switch (state) {
      case _BodyCheckState.fresh:
        bg = AppColors.grey;
        fg = AppColors.green;
        title = isKo ? '체형 분석 완료!' : 'Body scan complete!';
        subtitle = isKo
            ? '다음 확인까지 $daysUntilNext일'
            : '$daysUntilNext days until next check';
      case _BodyCheckState.dueSoon:
        bg = AppColors.purple.withValues(alpha: 0.18);
        fg = AppColors.purple;
        title = isKo ? '곧 체형을 다시 확인할 때야!' : 'Time to recheck your body soon!';
        subtitle = isKo
            ? '다음 측정까지 $daysUntilNext일'
            : '$daysUntilNext days until next check';
      case _BodyCheckState.overdue:
        bg = AppColors.red;
        fg = Colors.white;
        title = isKo ? '체형을 다시 확인할 때야!' : 'Time to recheck your body!';
        subtitle = isKo
            ? '마지막 측정 후 $_daysSinceLastCheck일이 지났어'
            : "It's been $_daysSinceLastCheck days since your last check";
    }

    return GestureDetector(
      onTap: () => context.push(RouteConstants.onboardingCapture),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: SvgPicture.asset(
                'assets/icons/home/alert.svg',
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: fg.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

// ── Weekly Goal Card ───────────────────────────────────────────────────────
class _WeeklyGoalCard extends ConsumerWidget {
  const _WeeklyGoalCard({required this.strings});
  final dynamic strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isKo = strings.locale == 'ko';
    final goal = ref.watch(weeklyWorkoutGoalProvider);
    final current = ref.watch(weeklyWorkoutsProvider);
    final allRecords = ref.watch(allRecordsProvider);
    final progress = (current / goal).clamp(0.0, 1.0);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final labels = isKo ? _weekdayLabelsKo : _weekdayLabelsEn;

    bool hasWorkoutOn(DateTime day) => allRecords.any((r) {
          final d = DateTime(r.date.year, r.date.month, r.date.day);
          return d == day;
        });

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isKo ? '이번 주 목표' : 'Weekly goal',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$current',
                      style: const TextStyle(
                        color: AppColors.green,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    TextSpan(
                      text: isKo ? ' / $goal회' : ' / $goal',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.green),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final date = monday.add(Duration(days: i));
              final _DayState state;
              if (date == today) {
                state = _DayState.today;
              } else if (date.isBefore(today) && hasWorkoutOn(date)) {
                state = _DayState.past;
              } else {
                state = _DayState.inactive;
              }
              return _WeekdayPill(
                  label: labels[i], state: state, isWeekday: i < 5);
            }),
          ),
        ],
      ),
    );
  }
}

enum _DayState { past, today, inactive }

class _WeekdayPill extends StatelessWidget {
  const _WeekdayPill({
    required this.label,
    required this.state,
    required this.isWeekday,
  });
  final String label;
  final _DayState state;
  final bool isWeekday;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (state) {
      case _DayState.past:
        bg = AppColors.green;
        fg = AppColors.black;
      case _DayState.today:
        bg = AppColors.purple;
        fg = Colors.white;
      case _DayState.inactive:
        bg = Colors.white.withValues(alpha: 0.06);
        fg = Colors.white.withValues(alpha: 0.35);
    }
    return Container(
      width: 42,
      height: 30,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: isWeekday ? FontWeight.w800 : FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ── Section Header ─────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailing,
    this.onTrailingTap,
  });
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        if (trailing != null)
          GestureDetector(
            onTap: onTrailingTap,
            child: Text(
              trailing!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Recent Record Tile ─────────────────────────────────────────────────────
class _RecentRecordTile extends StatelessWidget {
  const _RecentRecordTile({required this.record, required this.strings});
  final WorkoutRecordModel record;
  final dynamic strings;

  String _timeAgo(DateTime date, dynamic s) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return s.today;
    if (diff.inDays == 1) return s.yesterday;
    return '${diff.inDays}${s.daysAgo}';
  }

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final isKo = s.locale == 'ko';
    final ex = findExercise(record.exerciseId);

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
          'targetSets': 0,
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
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: SvgPicture.asset(
                'assets/icons/nav/workout.svg',
                width: 20,
                height: 20,
                colorFilter:
                    const ColorFilter.mode(AppColors.black, BlendMode.srcIn),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isKo ? ex.nameKr : record.exerciseName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    () {
                      final weight = mockWeightKgByExercise[record.exerciseId];
                      final weightPart = (weight == null || weight == 0)
                          ? ''
                          : ' · ${weight}kg';
                      return isKo
                          ? '${record.targetSets}세트 × ${record.totalReps}회$weightPart'
                          : '${record.targetSets} sets × ${record.totalReps} reps$weightPart';
                    }(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _timeAgo(record.date, s),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kori's Comment Card (최근 기록/피드백 없으면 코리가 안내) ──────────────
class _KoriCommentCard extends StatelessWidget {
  const _KoriCommentCard({required this.recent, required this.strings});
  final List<WorkoutRecordModel> recent;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final isKo = strings.locale == 'ko';
    final String message;
    if (recent.isEmpty) {
      message = isKo
          ? '아직 기록이 없어! 운동 시작 버튼을 클릭해 오늘 첫 기록을 남겨볼까?'
          : "No recent records yet! Pick a workout below and log your first one.";
    } else {
      final latest = recent.first;
      message = latest.feedbackNotes.isNotEmpty
          ? latest.feedbackNotes.first
          : (isKo
              ? '오늘도 수고했어! 다음에도 좋은 자세로 만나자.'
              : 'Nice work today! See you next time with great form.');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/images/character/face2.png',
            width: 62,
            height: 62,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isKo ? '코리의 한마디' : "Kori's tip",
                  style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
