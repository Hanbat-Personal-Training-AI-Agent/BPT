import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/dto/workout_metadata_dto.dart';
import '../../../data/mock_data.dart';
import '../../../services/workout_records_service.dart';
import '../data/workout_evidence.dart';
import 'deep_analysis_report_screen.dart';

const _monthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdaysKo = ['월', '화', '수', '목', '금', '토', '일'];
const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 운동한 날짜·시각 라벨. 예) `9월 9일 (수) 오후 3:20`, `Wed, Sep 9, 3:20 PM`
String _formatWorkoutDateTime(DateTime date, bool isKo) {
  final hour12raw = date.hour % 12;
  final hour12 = hour12raw == 0 ? 12 : hour12raw;
  final minute = date.minute.toString().padLeft(2, '0');
  final isAm = date.hour < 12;
  if (isKo) {
    final period = isAm ? '오전' : '오후';
    return '${date.month}월 ${date.day}일 (${_weekdaysKo[date.weekday - 1]}) '
        '$period $hour12:$minute';
  }
  final period = isAm ? 'AM' : 'PM';
  return '${_weekdaysEn[date.weekday - 1]}, ${_monthsEn[date.month - 1]} '
      '${date.day}, $hour12:$minute $period';
}

String _groupThousands(num n) {
  final raw = n.abs().toString();
  if (raw.contains('e')) return n.toString();
  final parts = raw.split('.');
  final digits = parts.first;
  final fraction = parts.length > 1 && parts[1] != '0' ? '.${parts[1]}' : '';
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return (n < 0 ? '-' : '') + buf.toString() + fraction;
}

/// 완료된 세트 1개의 기록 (반복 수 / 무게 / 자세 이슈 횟수).
class _SetRecord {
  const _SetRecord({
    required this.reps,
    required this.weightKg,
    required this.badCount,
    this.videoPath,
  });
  final int reps;
  final num weightKg;
  final int? badCount;
  final String? videoPath;
}

class WorkoutResultScreen extends ConsumerStatefulWidget {
  const WorkoutResultScreen({super.key, required this.result});
  final Map<String, dynamic> result;

  @override
  ConsumerState<WorkoutResultScreen> createState() =>
      _WorkoutResultScreenState();
}

class _WorkoutResultScreenState extends ConsumerState<WorkoutResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  final _screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();

    final isHistory = widget.result['isHistory'] as bool? ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isHistory) {
        _saveRecord();
      }
    });
  }

  /// Transmits strictly lightweight On-Device AI Metadata to Spring Boot
  Future<void> _saveRecord() async {
    final r = widget.result;
    final dto = WorkoutMetadataRequestDto(
      weightKg: _heaviestSetWeightKg(),
      clientRecordId: r['clientRecordId'] as String? ?? newClientRecordId(),
      exerciseId: r['exerciseId'] as String? ?? 'squat',
      exerciseName: r['exerciseName'] as String? ?? 'Squat',
      date: DateTime.now(),
      totalReps: r['totalReps'] as int? ?? 0,
      correctReps: r['correctReps'] as int? ?? 0,
      incorrectReps: r['incorrectReps'] as int? ?? 0,
      durationSeconds: r['elapsedSeconds'] as int? ?? 0,
      postureScore: (r['postureScore'] as num?)?.toDouble(),
      poseMetricsSummary: WorkoutEvidence.summaryObject(r['poseMetricsSummary']),
      feedbackNotes: (r['feedbackHistory'] as List?)?.cast<String>() ?? [],
      targetReps: r['targetReps'] as int? ?? 0,
      targetSets: r['targetSets'] as int? ?? 1,
      setsDetail: _setsDetail(),
      feedbackCounts: (r['feedbackCounts'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)) ??
          const {},
    );

    await ref.read(workoutRecordsProvider.notifier).addMetadataRecord(dto);
  }

  /// 운동 화면이 넘긴 세트별 기록(`setResults`)을 서버 setsDetail 로 바꾼다.
  List<WorkoutSetDetail> _setsDetail() {
    final raw = widget.result['setResults'];
    if (raw is! List) return const [];
    return [
      for (final (i, e) in raw.indexed)
        if (e is Map)
          WorkoutSetDetail(
            setNumber: i + 1,
            reps: (e['reps'] as num?)?.toInt() ?? 0,
            weightKg: (e['weightKg'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  /// 기록에는 무게를 하나만 저장하므로, 세트마다 무게가 다르면 가장 무거운
  /// 세트의 무게를 대표값으로 쓴다. 세트 정보가 없으면 운동별 기본 무게.
  double _heaviestSetWeightKg() {
    final exerciseId = widget.result['exerciseId'] as String? ?? 'squat';
    final raw = widget.result['setResults'];
    final weights = raw is List
        ? raw
            .map((e) => ((e as Map)['weightKg'] as num?)?.toDouble() ?? 0)
            .toList()
        : const <double>[];
    if (weights.isNotEmpty) return weights.reduce(math.max);
    return (mockWeightKgByExercise[exerciseId] ?? 0).toDouble();
  }

  /// 세트별 원본 기록(`setResults`)이 넘어온 경우 그대로 쓰고, 과거 기록
  /// 조회처럼 세트별 값이 없는 경우에는 합계를 세트 수만큼 균등하게 나눠
  /// 근사치로 보여준다.
  List<_SetRecord> _buildSetRecords({
    required int targetSets,
    required int totalReps,
    required num weightKg,
  }) {
    final summary = WorkoutEvidence.summaryObject(widget.result['poseMetricsSummary']);
    final raw = widget.result['setResults'] ?? WorkoutEvidence.details(summary, completedReps: totalReps)?['sets'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return _SetRecord(
          reps: (m['reps'] as num?)?.toInt() ?? 0,
          weightKg: (m['weightKg'] as num?) ?? weightKg,
          badCount: (m['badCount'] as num?)?.toInt(),
          videoPath: m['videoLocalPath'] as String?,
        );
      }).toList();
    }

    final sets = targetSets > 0 ? targetSets : 1;
    final baseReps = totalReps ~/ sets;
    final repsRemainder = totalReps % sets;
    return List.generate(sets, (i) {
      return _SetRecord(
        reps: baseReps + (i < repsRemainder ? 1 : 0),
        weightKg: weightKg,
        badCount: null, // Legacy correctness counters cannot locate or identify warning events.
      );
    });
  }

  Future<void> _onSharePressed() async {
    try {
      final bytes = await _screenshotController.capture(pixelRatio: 3);
      if (bytes == null) return;
      await Share.shareXFiles([
        XFile.fromData(bytes, name: 'bpt_workout_result.png', mimeType: 'image/png'),
      ]);
    } catch (_) {
      // 공유 시트를 열지 못해도 화면 이용에는 지장이 없으므로 조용히 무시한다.
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final isKo = s.locale == 'ko';
    final r = widget.result;

    final isHistory = r['isHistory'] as bool? ?? false;
    final date = r['date'] as DateTime? ?? DateTime.now();
    final exerciseId = r['exerciseId'] as String? ?? 'squat';
    final exerciseName = isKo
        ? (r['exerciseNameKr'] as String? ?? r['exerciseName'] as String? ?? '')
        : (r['exerciseName'] as String? ?? '');

    final totalReps = r['totalReps'] as int? ?? 0;
    final elapsedSec = r['elapsedSeconds'] as int? ?? 0;
    final targetReps = r['targetReps'] as int? ?? 0;
    var targetSets = r['targetSets'] as int? ?? 0;

    // 과거 기록에 저장된 무게가 있으면 그걸 쓰고, 없으면 운동별 기본값.
    final recordedWeight = (r['weightKg'] as num?) ?? 0;
    final weightKg = recordedWeight > 0
        ? recordedWeight
        : mockWeightKgByExercise[exerciseId] ?? 0;
    final setRecords = _buildSetRecords(
      targetSets: targetSets > 0 ? targetSets : 1,
      totalReps: totalReps,
      weightKg: weightKg,
    );
    if (targetSets <= 0) targetSets = setRecords.length;
    final evidence = WorkoutEvidence.details(WorkoutEvidence.summaryObject(r['poseMetricsSummary']), completedReps: totalReps);
    final completedSets = evidence != null ? (evidence['sets'] as List).length : targetSets;

    final volume =
        setRecords.fold<num>(0, (sum, set) => sum + set.reps * set.weightKg);

    final achievementPct = WorkoutEvidence.completionPercent(totalReps, targetReps);
    final achieved = achievementPct == 100;

    final historyTitle = _formatWorkoutDateTime(date, isKo);

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                isHistory: isHistory,
                isKo: isKo,
                historyTitle: historyTitle,
                onShare: _onSharePressed,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Screenshot(
                      controller: _screenshotController,
                      child: ColoredBox(
                        color: AppColors.black,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _HeroCard(
                                isKo: isKo,
                                date: date,
                                exerciseName: exerciseName,
                                achieved: achieved,
                                achievementPct: achievementPct,
                              ),
                              const SizedBox(height: 8),
                              Text(isKo ? '전체 자세 판정: 미확인 · 완료율은 수행 횟수 기준' : 'Overall form unassessed · completion uses performed reps',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                              const SizedBox(height: 16),
                              _StatsRow(
                                isKo: isKo,
                                sets: completedSets,
                                totalReps: totalReps,
                                volume: volume,
                                elapsedSec: elapsedSec,
                              ),
                              const SizedBox(height: 16),
                              _SetRecordsCard(
                                isKo: isKo,
                                records: setRecords,
                              ),
                              const SizedBox(height: 16),
                              _FeedbackCard(
                                isKo: isKo,
                                records: setRecords,
                              ),
                              const SizedBox(height: 16),
                              _ReplaySection(isKo: isKo, records: setRecords),
                              const SizedBox(height: 16),
                              DeepAnalysisSection(recordId: r['clientRecordId'] as String?),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: _BottomActions(
              isKo: isKo,
              onOtherWorkout: () => context.go(RouteConstants.exerciseSelection),
              onViewReport: () => context.go(RouteConstants.report),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header (고정, 스크롤 영향 없음) ─────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({
    required this.isHistory,
    required this.isKo,
    required this.historyTitle,
    required this.onShare,
  });
  final bool isHistory;
  final bool isKo;
  final String historyTitle;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          if (isHistory) ...[
            GestureDetector(
              onTap: () => context.pop(),
              behavior: HitTestBehavior.opaque,
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              isHistory
                  ? historyTitle
                  : (isKo ? '오늘 운동 끝! 수고했어' : 'Workout done! Nice work'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (!isHistory)
            GestureDetector(
              onTap: onShare,
              behavior: HitTestBehavior.opaque,
              child: Text(
                isKo ? '공유' : 'Share',
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Hero Card (날짜/운동명/목표달성 배지 + 코리 + 반짝임 장식) ─────────────
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.isKo,
    required this.date,
    required this.exerciseName,
    required this.achieved,
    required this.achievementPct,
  });
  final bool isKo;
  final DateTime date;
  final String exerciseName;
  final bool achieved;
  final int? achievementPct;

  static const double _cardHeight = 112;
  static const double _characterSize = 230;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: double.infinity,
            height: _cardHeight,
            color: AppColors.green,
            padding: const EdgeInsets.fromLTRB(26, 0, 0, 0),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatWorkoutDateTime(date, isKo),
                      style: TextStyle(
                        color: AppColors.black.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      exerciseName,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.black,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        achieved
                            ? (isKo ? '목표 횟수 완료!' : 'Rep goal completed!')
                            : (isKo
                                ? (achievementPct == null ? '목표 횟수 미기록' : '목표 횟수 $achievementPct% 완료')
                                : (achievementPct == null ? 'Rep goal not recorded' : '$achievementPct% of rep goal completed')),
                        style: TextStyle(
                          color: achieved ? Colors.white : AppColors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  right: 25,
                  child: Image.asset(
                    'assets/images/character/cheering.png',
                    width: _characterSize,
                    height: _characterSize,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: -7,
          right: 60,
          child: Transform.rotate(
            angle: 45 * math.pi / 180,
            child: Image.asset(
              'assets/images/decoration/spark_purple.png',
              width: 50,
              height: 50,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Stats Row (세트 / 총 반복 / 볼륨 / 시간) ────────────────────────────────
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.isKo,
    required this.sets,
    required this.totalReps,
    required this.volume,
    required this.elapsedSec,
  });
  final bool isKo;
  final int sets;
  final int totalReps;
  final num volume;
  final int elapsedSec;

  @override
  Widget build(BuildContext context) {
    final m = (elapsedSec ~/ 60).toString().padLeft(2, '0');
    final sec = (elapsedSec % 60).toString().padLeft(2, '0');
    return Row(
      children: [
        Expanded(
          child: _ResultStatTile(
              value: '$sets', label: isKo ? '세트' : 'Sets'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ResultStatTile(
              value: '$totalReps', label: isKo ? '총 반복' : 'Total reps'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ResultStatTile(
              value: _groupThousands(volume),
              label: isKo ? '볼륨 kg' : 'Volume kg'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ResultStatTile(value: '$m:$sec', label: isKo ? '시간' : 'Time'),
        ),
      ],
    );
  }
}

class _ResultStatTile extends StatelessWidget {
  const _ResultStatTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 세트별 기록 ──────────────────────────────────────────────────────────
class _SetRecordsCard extends StatelessWidget {
  const _SetRecordsCard({
    required this.isKo,
    required this.records,
  });
  final bool isKo;
  final List<_SetRecord> records;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isKo ? '세트별 기록' : 'Set breakdown',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _SetRecordRow(
              index: i + 1,
              record: records[i],
              isKo: isKo,
            ),
          ],
        ],
      ),
    );
  }
}

class _SetRecordRow extends StatelessWidget {
  const _SetRecordRow({
    required this.index,
    required this.record,
    required this.isKo,
  });
  final int index;
  final _SetRecord record;
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    final noRecordedWarnings = record.badCount == 0;
    final tag = record.badCount == null
        ? (isKo ? '경고 기록 미확인' : 'Warning record unavailable')
        : noRecordedWarnings
        ? (isKo ? '완료' : 'Completed')
        : (isKo ? '경고 ${record.badCount}회' : 'Warnings x${record.badCount}');
    final tagColor = noRecordedWarnings || record.badCount == null
        ? Colors.white.withValues(alpha: 0.65)
        : AppColors.red;

    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          isKo
              ? '${record.reps}회 · ${record.weightKg}kg'
              : '${record.reps} reps · ${record.weightKg}kg',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          tag,
          style: TextStyle(
            color: tagColor,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ── 코리 피드백 카드 ────────────────────────────────────────────────────
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.isKo,
    required this.records,
  });
  final bool isKo;
  final List<_SetRecord> records;

  @override
  Widget build(BuildContext context) {
    final badIndices = [
      for (var i = 0; i < records.length; i++)
        if ((records[i].badCount ?? 0) > 0) i + 1,
    ];
    final String message;
    final String character;
    if (records.any((r) => r.badCount == null)) {
      character = 'assets/images/character/face2.png';
      message = isKo ? '경고 기록의 범위를 확인할 수 없어.\n수행 기록을 확인해줘.' : 'Warning evidence is unavailable.\nReview the completion record.';
    } else if (badIndices.isEmpty) {
      character = 'assets/images/character/face2.png';
      message = isKo
          ? '기록된 경고는 없어.\n세트 마치느라 수고했어!'
          : 'No warnings were recorded.\nNice work completing your sets!';
    } else {
      character = 'assets/images/character/worrying.png';
      final setsLabelKo = badIndices.join('·');
      final setsLabelEn = badIndices.join(', ');
      message = isKo
          ? '$setsLabelKo세트에 경고가 기록됐어.\n세부 내용을 확인해줘.'
          : 'Warnings were recorded on set $setsLabelEn.\nReview the details.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.pink,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 레이아웃 높이는 기존(46)으로 고정하고 이미지만 위아래로 넘쳐 보이게 해서
          // 카드 높이는 늘리지 않는다.
          SizedBox(
            width: 72,
            height: 56,
            child: OverflowBox(
              maxWidth: 72,
              maxHeight: 72,
              child: Image.asset(character,
                  width: 72, height: 72, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 동작 다시보기 ────────────────────────────────────────────────────────
class _ReplaySection extends StatefulWidget {
  const _ReplaySection({required this.isKo, required this.records});
  final bool isKo;
  final List<_SetRecord> records;

  @override
  State<_ReplaySection> createState() => _ReplaySectionState();
}

class _ReplaySectionState extends State<_ReplaySection> {
  // 세트 녹화(BPT_SET_RECORDING)가 꺼져 기기 영상이 없으면 예전처럼 데모 영상 하나를 보여 준다.
  static const _demoVideoUrl = 'https://www.w3schools.com/html/mov_bbb.mp4';

  late int _index;
  VideoPlayerController? _controller;
  bool _savingVideo = false;

  @override
  void initState() {
    super.initState();
    _index = _defaultIndex();
  }

  int _defaultIndex() {
    if (widget.records.isEmpty) return 0;
    var best = 0;
    var bestBad = -1;
    for (var i = 0; i < widget.records.length; i++) {
      if ((widget.records[i].badCount ?? 0) > bestBad) {
        bestBad = widget.records[i].badCount ?? 0;
        best = i;
      }
    }
    return best;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _switchSet(int delta) {
    final next = (_index + delta).clamp(0, widget.records.length - 1);
    if (next == _index) return;
    _controller?.pause();
    _controller?.dispose();
    setState(() { _controller = null; _index = next; });
  }

  /// 지금 보고 있는 세트의 기기 녹화 파일을 갤러리에 저장한다.
  Future<void> _saveCurrentSetVideo() async {
    if (_savingVideo || widget.records.isEmpty) return;
    final isKo = widget.isKo;
    final setNo = _index + 1;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingVideo = true);
    File? tmp;
    try {
      final path = widget.records[_index].videoPath;
      if (path != null && await File(path).exists()) {
        if (!await Gal.hasAccess() && !await Gal.requestAccess()) throw const FileSystemException();
        await Gal.putVideo(path);
      } else {
        tmp = File(
            '${Directory.systemTemp.path}/bpt_set${setNo}_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await Dio().download(_demoVideoUrl, tmp.path);
        await Gal.putVideo(tmp.path, album: 'BPT');
      }
      messenger.showSnackBar(SnackBar(
        content: Text(isKo
            ? '$setNo세트 영상을 갤러리에 저장했어!'
            : 'Set $setNo video saved to your gallery!'),
        backgroundColor: AppColors.grey,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(
            isKo ? '영상 저장에 실패했어. 다시 시도해줘.' : 'Failed to save video. Try again.'),
        backgroundColor: AppColors.red,
      ));
    } finally {
      try {
        await tmp?.delete();
      } catch (_) {}
      if (mounted) setState(() => _savingVideo = false);
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) {
      final path = widget.records[_index].videoPath;
      final c = path != null && await File(path).exists()
          ? VideoPlayerController.file(File(path))
          : VideoPlayerController.networkUrl(Uri.parse(_demoVideoUrl));
      try {
        await c.initialize();
        c.setLooping(true);
        if (!mounted) {
          c.dispose();
          return;
        }
        setState(() => _controller = c);
        c.play();
      } catch (_) {
        // 네트워크 문제 등으로 재생 준비가 안 되면 조용히 무시한다.
      }
      return;
    }
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isKo = widget.isKo;
    final record = widget.records.isEmpty ? null : widget.records[_index];
    final durationLabel =
        record == null ? '0' : (4 + record.reps ~/ 2).toString();

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
                isKo ? '동작 다시보기' : 'Watch replay',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              GestureDetector(
                onTap: _savingVideo ? null : _saveCurrentSetVideo,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_savingVideo)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(AppColors.green),
                          ),
                        )
                      else
                        const Icon(Icons.download_rounded,
                            size: 14, color: AppColors.green),
                      const SizedBox(width: 4),
                      Text(
                        isKo ? '영상 저장' : 'Save video',
                        style: const TextStyle(
                          color: AppColors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ReplayArrowButton(
                icon: Icons.chevron_left_rounded,
                onTap: _index > 0 ? () => _switchSet(-1) : null,
              ),
              Expanded(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (_controller?.value.isPlaying ?? false)
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: AppColors.black,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isKo
                          ? '${_index + 1}세트 · $durationLabel초'
                          : 'Set ${_index + 1} · ${durationLabel}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ReplayProgressBar(controller: _controller),
                  ],
                ),
              ),
              _ReplayArrowButton(
                icon: Icons.chevron_right_rounded,
                onTap: _index < widget.records.length - 1
                    ? () => _switchSet(1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplayArrowButton extends StatelessWidget {
  const _ReplayArrowButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.03),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: enabled ? 0.8 : 0.25),
          size: 22,
        ),
      ),
    );
  }
}

class _ReplayProgressBar extends StatelessWidget {
  const _ReplayProgressBar({required this.controller});
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return Container(
        width: 90,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final total = value.duration.inMilliseconds;
        final progress =
            total == 0 ? 0.0 : (value.position.inMilliseconds / total).clamp(0.0, 1.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 90,
            height: 4,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(AppColors.green),
            ),
          ),
        );
      },
    );
  }
}

// ── 하단 액션 버튼 (다른 운동하러가기 / 기록 보기) ───────────────────────────────
class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.isKo,
    required this.onOtherWorkout,
    required this.onViewReport,
  });
  final bool isKo;
  final VoidCallback onOtherWorkout;
  final VoidCallback onViewReport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onOtherWorkout,
            child: Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                isKo ? '다른 운동' : 'Another',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: onViewReport,
            child: Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                isKo ? '기록 보기' : 'View report',
                style: const TextStyle(
                  color: AppColors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
