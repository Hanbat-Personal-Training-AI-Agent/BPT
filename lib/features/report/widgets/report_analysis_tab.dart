import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/report_analysis_provider.dart';

/// 리포트 > 분석 탭 본문.
///
/// ⚠️ 종목별 비율과 자주 나온 실수는 아직 목데이터다. [reportAnalysisProvider]
/// 참고 — 실제 집계가 생기면 그 provider만 교체하면 된다.
class ReportAnalysisTab extends ConsumerWidget {
  const ReportAnalysisTab({super.key, required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(reportAnalysisProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        children: [
          _ExerciseRatioCard(isKo: isKo, data: data),
          const SizedBox(height: 12),
          _MistakesCard(isKo: isKo, data: data),
          const SizedBox(height: 12),
          _InsightCard(isKo: isKo, data: data),
        ],
      ),
    );
  }
}

// ── 종목별 비율 (도넛 차트) ─────────────────────────────────────────────────
class _ExerciseRatioCard extends StatelessWidget {
  const _ExerciseRatioCard({required this.isKo, required this.data});
  final bool isKo;
  final ReportAnalysisData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isKo ? '종목별 비율' : 'Ratio by exercise',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RatioDonut(isKo: isKo, data: data),
              const SizedBox(width: 24),
              Expanded(child: _RatioLegend(isKo: isKo, data: data)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatioDonut extends StatelessWidget {
  const _RatioDonut({required this.isKo, required this.data});
  final bool isKo;
  final ReportAnalysisData data;

  static const _size = 130.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: _size * 0.34,
              startDegreeOffset: -90,
              sections: [
                for (final r in data.ratios)
                  PieChartSectionData(
                    value: r.percent.toDouble(),
                    color: r.color,
                    radius: _size * 0.16,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${data.totalSessions}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                isKo ? '세션' : 'sessions',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatioLegend extends StatelessWidget {
  const _RatioLegend({required this.isKo, required this.data});
  final bool isKo;
  final ReportAnalysisData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in data.ratios) ...[
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: r.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.label(isKo),

                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${r.percent}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (r != data.ratios.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

// ── 자주 나온 실수 ─────────────────────────────────────────────────────────
class _MistakesCard extends StatelessWidget {
  const _MistakesCard({required this.isKo, required this.data});
  final bool isKo;
  final ReportAnalysisData data;

  @override
  Widget build(BuildContext context) {
    final maxCount = data.mistakes.fold<int>(
        0, (a, m) => m.count > a ? m.count : a);
    return Container(
      width: double.infinity,
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
                isKo ? '자주 나온 실수' : 'Common mistakes',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                isKo
                    ? '총 ${data.totalMistakes}회'
                    : 'Total ${data.totalMistakes}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final m in data.mistakes) ...[
            _MistakeRow(isKo: isKo, item: m, maxCount: maxCount),
            if (m != data.mistakes.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _MistakeRow extends StatelessWidget {
  const _MistakeRow({
    required this.isKo,
    required this.item,
    required this.maxCount,
  });
  final bool isKo;
  final MistakeItem item;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount <= 0 ? 0.0 : item.count / maxCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              item.label(isKo),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              isKo ? '${item.count}회' : '${item.count}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Container(
                  height: 7,
                  width: constraints.maxWidth,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: fraction),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, f, _) => Container(
                    height: 7,
                    width: constraints.maxWidth * f,
                    color: item.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 코리 인사이트 ──────────────────────────────────────────────────────────
class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.isKo, required this.data});
  final bool isKo;
  final ReportAnalysisData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset('assets/images/character/face2.png',
              width: 64, height: 64, fit: BoxFit.contain),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              data.insight(isKo),
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
