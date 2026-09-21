import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/report_provider.dart';
import '../widgets/report_volume_tab.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isKo = ref.watch(selectedLanguageProvider) == 'ko';
    final section = ref.watch(reportSectionProvider);

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 고정 영역: 제목과 탭은 스크롤에 영향받지 않음
              _ReportHeader(isKo: isKo),
              _SectionTabs(
                isKo: isKo,
                current: section,
                onChanged: (s) =>
                    ref.read(reportSectionProvider.notifier).state = s,
              ),
              Expanded(
                child: section == ReportSection.volume
                    ? ReportVolumeTab(isKo: isKo)
                    : _AnalysisPlaceholder(isKo: isKo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 제목 + 현재 연월 ───────────────────────────────────────────────────────
class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            isKo ? '리포트' : 'Report',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${now.year}. $month',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 운동량 / 분석 탭 ───────────────────────────────────────────────────────
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.isKo,
    required this.current,
    required this.onChanged,
  });
  final bool isKo;
  final ReportSection current;
  final ValueChanged<ReportSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      ReportSection.volume: isKo ? '운동량' : 'Volume',
      ReportSection.analysis: isKo ? '분석' : 'Analysis',
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          for (final section in ReportSection.values) ...[
            GestureDetector(
              onTap: () => onChanged(section),
              behavior: HitTestBehavior.opaque,
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      labels[section]!,
                      style: TextStyle(
                        color: section == current
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.35),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: section == current
                            ? AppColors.green
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
          ],
        ],
      ),
    );
  }
}

// ── 분석 탭 (아직 구현 전) ─────────────────────────────────────────────────
class _AnalysisPlaceholder extends StatelessWidget {
  const _AnalysisPlaceholder({required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        isKo ? '분석 화면은 곧 만나볼 수 있어요' : 'Analysis is coming soon',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
