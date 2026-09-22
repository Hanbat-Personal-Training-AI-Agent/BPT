import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/report_provider.dart';

String _groupThousands(int n) {
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return (n < 0 ? '-' : '') + buf.toString();
}

String _formatDuration(int totalSeconds) {
  final totalMinutes = totalSeconds ~/ 60;
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

String _formatMinutes(double minutes) => _formatDuration(minutes.round() * 60);

/// y축 눈금용 짧은 시간 표기: 0 / 30m / 1h / 1.5h. 왼쪽 자리를 적게 차지하도록
/// 시간 단위는 소수점 한 자리까지만 쓴다.
String _formatAxisMinutes(double minutes) {
  final m = minutes.round();
  if (m <= 0) return '0';
  if (m < 60) return '${m}m';
  final h = m / 60;
  return h == h.roundToDouble() ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';
}

/// 막대 차트의 y축 범위. 눈금은 0, [step], 2*[step], ... [max]이다.
class ChartAxis {
  const ChartAxis({required this.max, required this.step});
  final double max;
  final double step;

  List<double> get ticks => [
        for (var v = 0.0; v <= max + 0.001; v += step) v,
      ];
}

/// 가장 큰 값([maxMinutes])이 들어가는 깔끔한 y축을 고른다. 눈금 간격은 5/10/15/
/// 20/30분, 그 위로는 1시간 단위로 정하고, 눈금은 최대 4개(간격 3칸 이하)가
/// 되도록 가장 작은 간격을 쓴다.
ChartAxis niceTimeAxis(double maxMinutes) {
  if (maxMinutes <= 0) return const ChartAxis(max: 60, step: 30);
  const steps = [5.0, 10.0, 15.0, 20.0, 30.0, 60.0, 120.0, 180.0, 240.0, 300.0];
  var step = steps.last;
  var found = false;
  for (final s in steps) {
    if (maxMinutes / s <= 3) {
      step = s;
      found = true;
      break;
    }
  }
  if (!found) {
    // 30시간을 넘는 경우: 1시간의 배수로 올려 3칸 안에 들어오게 한다.
    step = (maxMinutes / 3 / 60).ceil() * 60.0;
  }
  return ChartAxis(max: (maxMinutes / step).ceil() * step, step: step);
}

/// 반복 횟수 차트용 y축. 눈금 간격은 1/2/5 x 10^n 중에서 눈금이 최대 4개(간격 3칸
/// 이하)가 되는 가장 작은 값을 쓴다. (예: 최댓값 143 -> 0/50/100/150)
ChartAxis niceCountAxis(double maxCount) {
  if (maxCount <= 0) return const ChartAxis(max: 100, step: 50);
  var magnitude = 1.0;
  while (true) {
    for (final m in const [1.0, 2.0, 5.0]) {
      final step = m * magnitude;
      if (maxCount / step <= 3) {
        return ChartAxis(max: (maxCount / step).ceil() * step, step: step);
      }
    }
    magnitude *= 10;
  }
}

/// y축 눈금용 횟수 표기: 0 / 50 / 1k / 1.5k.
String _formatAxisCount(double value) {
  final v = value.round();
  if (v < 1000) return '$v';
  final k = v / 1000;
  return k == k.roundToDouble() ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
}

/// 막대 색: 이전 구간은 모두 보라, 현재(이번) 구간만 라임.
Color _barColorAt(int i) =>
    i == reportCurrentIndex ? AppColors.green : AppColors.purple;

/// 현재(이번) 구간의 x축 라벨만 라임으로 강조. 나머지는 null(기본 회색).
Color? _labelColorAt(int i) => i == reportCurrentIndex ? AppColors.green : null;

/// 리포트 > 운동량 탭 본문.
class ReportVolumeTab extends ConsumerWidget {
  const ReportVolumeTab({super.key, required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final data = ref.watch(reportVolumeProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        children: [
          _PeriodSelector(
            isKo: isKo,
            current: period,
            onChanged: (p) => ref.read(reportPeriodProvider.notifier).state = p,
          ),
          const SizedBox(height: 12),
          _StatsRow(isKo: isKo, data: data),
          const SizedBox(height: 12),
          _TimeChangeCard(isKo: isKo, data: data),
          const SizedBox(height: 12),
          _RepsChangeCard(isKo: isKo, data: data),
          const SizedBox(height: 12),
          _KoriCommentCard(isKo: isKo, data: data),
        ],
      ),
    );
  }
}

// ── 일별 / 주별 / 월별 ─────────────────────────────────────────────────────
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.isKo,
    required this.current,
    required this.onChanged,
  });
  final bool isKo;
  final ReportPeriod current;
  final ValueChanged<ReportPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      ReportPeriod.daily: isKo ? '일별' : 'Daily',
      ReportPeriod.weekly: isKo ? '주별' : 'Weekly',
      ReportPeriod.monthly: isKo ? '월별' : 'Monthly',
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (final period in ReportPeriod.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(period),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: period == current
                        ? AppColors.green
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    labels[period]!,
                    style: TextStyle(
                      color: period == current
                          ? AppColors.black
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 총 시간 / 총 반복 / 운동 일수 ──────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.isKo, required this.data});
  final bool isKo;
  final ReportVolumeData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: isKo ? '총 시간' : 'Total time',
            value: _formatDuration(data.totalSeconds),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: isKo ? '총 반복' : 'Total reps',
            value: _groupThousands(data.totalReps),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: isKo ? '운동 일수' : 'Active days',
            value: isKo ? '${data.activeDays}일' : '${data.activeDays}d',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 운동 시간 변화 ─────────────────────────────────────────────────────────
class _TimeChangeCard extends StatelessWidget {
  const _TimeChangeCard({required this.isKo, required this.data});
  final bool isKo;
  final ReportVolumeData data;

  @override
  Widget build(BuildContext context) {
    final axis =
        niceTimeAxis(data.minutes.fold<double>(0, (a, b) => a > b ? a : b));
    return _ChartCard(
      title: isKo ? '운동 시간 변화' : 'Workout time',
      // y축 글자 자리 때문에 그래프가 오른쪽으로 밀려 보여서, 그래프만 카드
      // 왼쪽 여백 쪽으로 조금 당긴다.
      chartLeftBleed: 8,
      trailing: _ChangeBadge(pct: data.timeChangePct),
      child: _BarChart(
        // 집계 단위를 바꾸면 선택된 막대를 초기화한다.
        key: ValueKey(data.period),
        keyPrefix: 'time-bar',
        values: data.minutes,
        colors: [for (var i = 0; i < reportBucketCount; i++) _barColorAt(i)],
        labels: data.labels,
        valueLabelOf: (i) => _formatMinutes(data.minutes[i]),
        axisMax: axis.max,
        axisTicks: axis.ticks,
        axisLabelOf: _formatAxisMinutes,
        labelColors: [
          for (var i = 0; i < reportBucketCount; i++) _labelColorAt(i)
        ],
        barAreaHeight: 112,
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.pct});
  final int? pct;

  @override
  Widget build(BuildContext context) {
    final p = pct;
    if (p == null) return const SizedBox.shrink();
    final Color bg;
    final Color fg;
    if (p > 0) {
      bg = AppColors.green;
      fg = AppColors.black;
    } else if (p < 0) {
      bg = AppColors.red;
      fg = Colors.white;
    } else {
      bg = Colors.white.withValues(alpha: 0.12);
      fg = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        p > 0 ? '+$p%' : '$p%',
        style: TextStyle(
          color: fg,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ── 반복 횟수 변화 ─────────────────────────────────────────────────────────
class _RepsChangeCard extends StatelessWidget {
  const _RepsChangeCard({required this.isKo, required this.data});
  final bool isKo;
  final ReportVolumeData data;

  @override
  Widget build(BuildContext context) {
    final axis =
        niceCountAxis(data.reps.fold<double>(0, (a, b) => a > b ? a : b));
    return _ChartCard(
      title: isKo ? '반복 횟수 변화' : 'Rep count',
      chartLeftBleed: 8,
      trailing: Text(
        isKo
            ? '평균 ${data.avgRepsPerActiveDay}회'
            : 'Avg ${data.avgRepsPerActiveDay}',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: _BarChart(
        key: ValueKey(data.period),
        keyPrefix: 'reps-bar',
        values: data.reps,
        colors: [for (var i = 0; i < reportBucketCount; i++) _barColorAt(i)],
        labels: data.labels,
        labelColors: [
          for (var i = 0; i < reportBucketCount; i++) _labelColorAt(i)
        ],
        valueLabelOf: (i) => isKo
            ? '${_groupThousands(data.reps[i].round())}회'
            : '${_groupThousands(data.reps[i].round())} reps',
        axisMax: axis.max,
        axisTicks: axis.ticks,
        axisLabelOf: _formatAxisCount,
        barAreaHeight: 112,
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.trailing,
    required this.child,
    this.chartLeftBleed = 0,
  });
  final String title;
  final Widget trailing;
  final Widget child;

  /// [child]를 카드 왼쪽 안쪽 여백 쪽으로 이만큼 당겨서 그린다. 제목 줄은 그대로
  /// 두고 차트만 왼쪽으로 넓어진다.
  final double chartLeftBleed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18 - chartLeftBleed, 18, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: chartLeftBleed),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                trailing,
              ],
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// 막대 하나가 구간 하나인 단순 막대 차트.
///
/// - [axisMax]/[axisTicks]/[axisLabelOf]를 주면 왼쪽에 y축 눈금과 옅은 가로선을
///   그리고, 막대 높이를 [axisMax] 기준으로 맞춘다. 없으면 가장 큰 값이 막대
///   영역을 채운다.
/// - [valueLabelOf]를 주면 막대를 눌렀을 때 그 막대 위에 값이 글자만 뜬다
///   (같은 막대를 다시 누르면 사라짐). 글자가 들어갈 위쪽 [_valueTextSpace]는
///   항상 비워 두고, [barAreaHeight]에 그 공간까지 포함한다.
/// - 값이 0인 구간도 사라지지 않도록 얇은 막대로 남긴다.
class _BarChart extends StatefulWidget {
  const _BarChart({
    super.key,
    required this.values,
    required this.colors,
    required this.barAreaHeight,
    this.labels,
    this.labelColors,
    this.valueLabelOf,
    this.keyPrefix,
    this.axisMax,
    this.axisTicks,
    this.axisLabelOf,
  });
  final List<double> values;
  final List<Color> colors;
  final double barAreaHeight;
  final List<String>? labels;
  final List<Color?>? labelColors;
  final String Function(int index)? valueLabelOf;
  final String? keyPrefix;
  final double? axisMax;
  final List<double>? axisTicks;
  final String Function(double value)? axisLabelOf;

  @override
  State<_BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<_BarChart> {
  static const _minBarHeight = 8.0;
  static const _valueTextSpace = 24.0;
  static const _valueTextWidth = 72.0;
  static const _axisWidth = 34.0;
  static const _axisLabelWidth = 28.0;

  int? _selected;

  void _onTap(int i) {
    if (widget.valueLabelOf == null) return;
    setState(() => _selected = _selected == i ? null : i);
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    final tappable = widget.valueLabelOf != null;
    final hasAxis = widget.axisMax != null && widget.axisTicks != null;
    final maxBarHeight = tappable
        ? widget.barAreaHeight - _valueTextSpace
        : widget.barAreaHeight;
    final dataMax = values.fold<double>(0, (a, b) => a > b ? a : b);
    final scaleMax = hasAxis ? widget.axisMax! : dataMax;
    double barHeightOf(int i) => scaleMax <= 0
        ? _minBarHeight
        : (values[i] / scaleMax * maxBarHeight)
            .clamp(_minBarHeight, maxBarHeight);

    final labels = widget.labels;
    final labelColors = widget.labelColors;
    final leftInset = hasAxis ? _axisWidth : 0.0;
    final gridColor = Colors.white.withValues(alpha: 0.06);

    return Column(
      children: [
        SizedBox(
          height: widget.barAreaHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (hasAxis)
                for (final tick in widget.axisTicks!) ...[
                  Positioned(
                    left: _axisWidth,
                    right: 0,
                    bottom: tick / scaleMax * maxBarHeight,
                    height: 1,
                    child: ColoredBox(color: gridColor),
                  ),
                  Positioned(
                    left: 0,
                    width: _axisLabelWidth,
                    // 눈금선 높이에 글자 가운데가 오도록 (글자 높이 16 기준).
                    bottom: tick / scaleMax * maxBarHeight - 8,
                    height: 16,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        widget.axisLabelOf!(tick),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              Positioned.fill(
                left: leftInset,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final slotWidth = constraints.maxWidth / values.length;
                    final selected = _selected;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < values.length; i++)
                              Expanded(
                                child: GestureDetector(
                                  key: widget.keyPrefix == null
                                      ? null
                                      : Key('${widget.keyPrefix}-$i'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: tappable ? () => _onTap(i) : null,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 3),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(end: barHeightOf(i)),
                                      duration:
                                          const Duration(milliseconds: 500),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, height, _) => Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          height: height,
                                          decoration: BoxDecoration(
                                            color: widget.colors[i],
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (selected != null)
                          Positioned(
                            // 막대 위에 글자만 띄운다. 항상 막대 가운데에 맞추고, 양 끝
                            // 막대에서는 글자가 그래프 영역 밖(y축 자리 / 카드 오른쪽
                            // 여백)으로 조금 나가도록 둔다. 안쪽으로 밀어 넣으면 글자가
                            // 막대에서 어긋나 보인다.
                            left: (selected + 0.5) * slotWidth -
                                _valueTextWidth / 2,
                            bottom: barHeightOf(selected) + 4,
                            width: _valueTextWidth,
                            child: IgnorePointer(
                              child: Text(
                                widget.valueLabelOf!(selected),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (labels != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.only(left: leftInset),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: TextStyle(
                        color: labelColors?[i] ??
                            Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight: labelColors?[i] != null
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── 코리 코멘트 ────────────────────────────────────────────────────────────
class _KoriCommentCard extends StatelessWidget {
  const _KoriCommentCard({required this.isKo, required this.data});
  final bool isKo;
  final ReportVolumeData data;

  String _message() {
    if (!data.hasData) {
      return isKo
          ? '아직 기록이 없어.\n오늘 첫 운동을 시작해볼까?'
          : 'No workouts yet.\nShall we start today?';
    }
    final pct = data.timeChangePct;
    final unit = switch (data.period) {
      ReportPeriod.daily => isKo ? '어제' : 'yesterday',
      ReportPeriod.weekly => isKo ? '지난주' : 'last week',
      ReportPeriod.monthly => isKo ? '지난달' : 'last month',
    };
    if (pct != null && pct >= 10) {
      return isKo
          ? '$unit부터 확 늘었어!\n지금 페이스 그대로 가보자'
          : 'You stepped it up from $unit!\nKeep this pace going.';
    }
    if (pct != null && pct <= -10) {
      return isKo
          ? '$unit엔 조금 줄었어.\n이번엔 다시 페이스를 올려보자!'
          : 'It dipped $unit.\nLet\'s pick the pace back up!';
    }
    return isKo
        ? '꾸준히 잘 하고 있어!\n이 리듬 그대로 이어가자'
        : 'You\'re staying consistent!\nKeep up this rhythm.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Image.asset('assets/images/character/face.png',
              width: 48, height: 48, fit: BoxFit.contain),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _message(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
