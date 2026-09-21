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
import '../providers/workout_provider.dart';

const _monthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// 운동별로 자세가 흐트러졌을 때 가장 흔히 지적되는 부위. 관절별 세부 분석
// 데이터가 아직 없어서, 운동 종류당 대표 부위 하나로 단순화해 보여준다.
const _issueBodyPartKo = <String, String>{
  'squat': '무릎',
  'benchpress': '가슴',
  'deadlift': '허리',
  'barbell-row': '허리',
  'pushup': '상체',
  'lat-pulldown': '어깨',
};
const _issueBodyPartEn = <String, String>{
  'squat': 'knees',
  'benchpress': 'chest',
  'deadlift': 'lower back',
  'barbell-row': 'lower back',
  'pushup': 'upper body',
  'lat-pulldown': 'shoulders',
};

String _groupThousands(int n) {
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return (n < 0 ? '-' : '') + buf.toString();
}

/// 완료된 세트 1개의 기록 (반복 수 / 무게 / 자세 이슈 횟수).
class _SetRecord {
  const _SetRecord({
    required this.reps,
    required this.weightKg,
    required this.badCount,
  });
  final int reps;
  final int weightKg;
  final int badCount;
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
        ref.read(workoutProvider.notifier).reset();
        _saveRecord();
      }
    });
  }

  /// Transmits strictly lightweight On-Device AI Metadata to Spring Boot
  Future<void> _saveRecord() async {
    final r = widget.result;
    final dto = WorkoutMetadataRequestDto(
      clientRecordId: DateTime.now().millisecondsSinceEpoch.toString(),
      exerciseId: r['exerciseId'] as String? ?? 'squat',
      exerciseName: r['exerciseName'] as String? ?? 'Squat',
      date: DateTime.now(),
      totalReps: r['totalReps'] as int? ?? 0,
      correctReps: r['correctReps'] as int? ?? 0,
      incorrectReps: r['incorrectReps'] as int? ?? 0,
      durationSeconds: r['elapsedSeconds'] as int? ?? 0,
      postureScore: (r['postureScore'] as num?)?.toDouble() ?? 0.0,
      feedbackNotes: (r['feedbackHistory'] as List?)?.cast<String>() ?? [],
      targetReps: r['targetReps'] as int? ?? 0,
      targetSets: r['targetSets'] as int? ?? 1,
    );

    await ref.read(workoutRecordsProvider.notifier).addMetadataRecord(dto);
  }

  /// 세트별 원본 기록(`setResults`)이 넘어온 경우 그대로 쓰고, 과거 기록
  /// 조회처럼 세트별 값이 없는 경우에는 합계를 세트 수만큼 균등하게 나눠
  /// 근사치로 보여준다.
  List<_SetRecord> _buildSetRecords({
    required int targetSets,
    required int totalReps,
    required int incorrectReps,
    required int weightKg,
  }) {
    final raw = widget.result['setResults'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return _SetRecord(
          reps: (m['reps'] as num?)?.toInt() ?? 0,
          weightKg: (m['weightKg'] as num?)?.toInt() ?? weightKg,
          badCount: (m['badCount'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    }

    final sets = targetSets > 0 ? targetSets : 1;
    final baseReps = totalReps ~/ sets;
    final repsRemainder = totalReps % sets;
    final baseBad = incorrectReps ~/ sets;
    final badRemainder = incorrectReps % sets;
    return List.generate(sets, (i) {
      return _SetRecord(
        reps: baseReps + (i < repsRemainder ? 1 : 0),
        weightKg: weightKg,
        badCount: baseBad + (i < badRemainder ? 1 : 0),
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
    final correctReps = r['correctReps'] as int? ?? totalReps;
    final incorrectReps =
        r['incorrectReps'] as int? ?? (totalReps - correctReps).clamp(0, totalReps);
    final elapsedSec = r['elapsedSeconds'] as int? ?? 0;
    final targetReps = r['targetReps'] as int? ?? 0;
    var targetSets = r['targetSets'] as int? ?? 0;

    final weightKg = mockWeightKgByExercise[exerciseId] ?? 0;
    final setRecords = _buildSetRecords(
      targetSets: targetSets > 0 ? targetSets : 1,
      totalReps: totalReps,
      incorrectReps: incorrectReps,
      weightKg: weightKg,
    );
    if (targetSets <= 0) targetSets = setRecords.length;

    final volume =
        setRecords.fold<int>(0, (sum, set) => sum + set.reps * set.weightKg);

    final achieved = targetReps > 0
        ? correctReps >= targetReps
        : (incorrectReps == 0 && totalReps > 0);
    final achievementPct = targetReps > 0
        ? ((correctReps / targetReps) * 100).clamp(0, 100).round()
        : (totalReps == 0 ? 0 : ((correctReps / totalReps) * 100).round());

    final historyTitle = isKo
        ? '${date.month}월 ${date.day}일 · $exerciseName'
        : '${_monthsEn[date.month - 1]} ${date.day} · $exerciseName';

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
                              const SizedBox(height: 16),
                              _StatsRow(
                                isKo: isKo,
                                sets: targetSets,
                                totalReps: totalReps,
                                volume: volume,
                                elapsedSec: elapsedSec,
                              ),
                              const SizedBox(height: 16),
                              _SetRecordsCard(
                                isKo: isKo,
                                exerciseId: exerciseId,
                                records: setRecords,
                              ),
                              const SizedBox(height: 16),
                              _FeedbackCard(
                                isKo: isKo,
                                exerciseId: exerciseId,
                                records: setRecords,
                              ),
                              const SizedBox(height: 16),
                              _ReplaySection(isKo: isKo, records: setRecords),
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
  final int achievementPct;

  static const double _cardHeight = 112;
  static const double _characterSize = 230;

  String _dateLabel() {
    final hour24 = date.hour;
    final isAm = hour24 < 12;
    final hour12raw = hour24 % 12;
    final hour12 = hour12raw == 0 ? 12 : hour12raw;
    final minute = date.minute.toString().padLeft(2, '0');
    if (isKo) {
      final period = isAm ? '오전' : '오후';
      return '${date.month}월 ${date.day}일 $period $hour12:$minute';
    }
    final period = isAm ? 'AM' : 'PM';
    return '${_monthsEn[date.month - 1]} ${date.day}, $hour12:$minute $period';
  }

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
                      _dateLabel(),
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
                            ? (isKo ? '목표 달성!' : 'Goal hit!')
                            : (isKo
                                ? '$achievementPct% 달성'
                                : '$achievementPct% done'),
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
  final int volume;
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
    required this.exerciseId,
    required this.records,
  });
  final bool isKo;
  final String exerciseId;
  final List<_SetRecord> records;

  @override
  Widget build(BuildContext context) {
    final bodyPart = isKo
        ? (_issueBodyPartKo[exerciseId] ?? _issueBodyPartKo['squat']!)
        : (_issueBodyPartEn[exerciseId] ?? _issueBodyPartEn['squat']!);

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
              bodyPart: bodyPart,
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
    required this.bodyPart,
  });
  final int index;
  final _SetRecord record;
  final bool isKo;
  final String bodyPart;

  @override
  Widget build(BuildContext context) {
    final ok = record.badCount == 0;
    final tag = ok
        ? (isKo ? '안정' : 'Stable')
        : (isKo ? '$bodyPart ${record.badCount}회' : '$bodyPart x${record.badCount}');
    final tagColor = ok ? AppColors.green : AppColors.red;

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
    required this.exerciseId,
    required this.records,
  });
  final bool isKo;
  final String exerciseId;
  final List<_SetRecord> records;

  @override
  Widget build(BuildContext context) {
    final badIndices = [
      for (var i = 0; i < records.length; i++)
        if (records[i].badCount > 0) i + 1,
    ];
    final bodyPartKo = _issueBodyPartKo[exerciseId] ?? _issueBodyPartKo['squat']!;
    final bodyPartEn = _issueBodyPartEn[exerciseId] ?? _issueBodyPartEn['squat']!;

    final String message;
    final String character;
    if (badIndices.isEmpty) {
      character = 'assets/images/character/face2.png';
      message = isKo
          ? '오늘 자세 다 좋았어!\n이 페이스 그대로 가자!'
          : 'Great form all the way through today!\nKeep this pace up.';
    } else {
      character = 'assets/images/character/worrying.png';
      final setsLabelKo = badIndices.join('·');
      final setsLabelEn = badIndices.join(', ');
      message = isKo
          ? '$setsLabelKo세트에서 $bodyPartKo이(가) 안쪽으로 모였어.\n다음엔 방향만 살짝 신경 써줘. 깊이랑 속도는 좋았어!'
          : 'Your $bodyPartEn drifted inward on set $setsLabelEn.\nWatch the direction next time — depth and tempo were great!';
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
  // 세트별 실제 녹화 저장소가 아직 없어서, 데모용 영상 하나를 세트 전환마다
  // 처음부터 다시 재생하는 방식으로 "세트별로 볼 수 있다"는 동작만 보여준다.
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
      if (widget.records[i].badCount > bestBad) {
        bestBad = widget.records[i].badCount;
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
    _controller?.seekTo(Duration.zero);
    setState(() => _index = next);
  }

  /// 지금 보고 있는 세트의 영상만 갤러리에 저장한다. 세트별 실제 녹화 파일이
  /// 생기면 [_demoVideoUrl] 대신 해당 세트의 파일 경로/URL을 넘기면 된다.
  Future<void> _saveCurrentSetVideo() async {
    if (_savingVideo || widget.records.isEmpty) return;
    final isKo = widget.isKo;
    final setNo = _index + 1;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingVideo = true);
    File? tmp;
    try {
      tmp = File(
          '${Directory.systemTemp.path}/bpt_set${setNo}_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await Dio().download(_demoVideoUrl, tmp.path);
      await Gal.putVideo(tmp.path, album: 'BPT');
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
      final c = VideoPlayerController.networkUrl(Uri.parse(_demoVideoUrl));
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
