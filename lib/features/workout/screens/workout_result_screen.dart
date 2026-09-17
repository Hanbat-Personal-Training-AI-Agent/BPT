import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/dto/workout_metadata_dto.dart';
import '../../../models/workout_record_model.dart';
import '../../../services/sync_service.dart';
import '../../../services/workout_records_service.dart';
import '../providers/workout_provider.dart';

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
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  VideoPlayerController? _vpCtrl;
  bool _vpReady = false;
  bool _showReplay = false;
  WorkoutRecordModel? _savedRecord;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
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

    final record = await ref
        .read(workoutRecordsProvider.notifier)
        .addMetadataRecord(dto);

    if (mounted && record != null) {
      setState(() {
        _savedRecord = record;
      });
    }
  }

  void _initVideoPlayer() {
    _vpCtrl = VideoPlayerController.networkUrl(
      Uri.parse('https://www.w3schools.com/html/mov_bbb.mp4'),
    );
    _vpCtrl!.initialize().then((_) {
      if (mounted) setState(() => _vpReady = true);
      _vpCtrl!.setLooping(true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _vpCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final syncStateAsync = ref.watch(workoutSyncProvider);
    final r = widget.result;

    final isHistory = r['isHistory'] as bool? ?? false;
    final date = r['date'] as DateTime?;
    final exerciseName = s.locale == 'ko'
        ? (r['exerciseNameKr'] as String? ?? r['exerciseName'] as String? ?? '')
        : (r['exerciseName'] as String? ?? '');
    final totalReps = r['totalReps'] as int? ?? 0;
    final correctReps = r['correctReps'] as int? ?? 0;
    final incorrectReps = r['incorrectReps'] as int? ?? 0;
    final elapsedSec = r['elapsedSeconds'] as int? ?? 0;
    final score = _savedRecord?.postureScore ?? ((r['postureScore'] as num?)?.toDouble() ?? 0.0);
    final feedbacks = (r['feedbackHistory'] as List?)?.cast<String>() ?? [];
    final targetReps = r['targetReps'] as int? ?? 0;

    final isSynced = _savedRecord?.isSynced ?? false;

    final accuracy =
        totalReps == 0 ? 0 : ((correctReps / totalReps) * 100).round();
    final achievement = targetReps == 0
        ? accuracy
        : ((correctReps / targetReps) * 100).clamp(0.0, 100.0).round();
    final m = elapsedSec ~/ 60;
    final sec = elapsedSec % 60;
    final duration = '${m}m ${sec}s';

    final scoreColor = score >= 90
        ? AppColors.scoreExcellent
        : score >= 75
            ? AppColors.scoreGood
            : score >= 60
                ? AppColors.scoreFair
                : AppColors.scorePoor;

    String appBarTitle = s.workoutComplete;
    if (isHistory && date != null) {
      appBarTitle = '${date.month}/${date.day}/${date.year}  •  $exerciseName';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        leading: IconButton(
          icon: Icon(isHistory
              ? Icons.arrow_back_ios_rounded
              : Icons.close_rounded),
          onPressed: () =>
              isHistory ? context.pop() : context.go(RouteConstants.home),
        ),
        actions: isHistory
            ? null
            : [
                TextButton(
                  onPressed: () =>
                      context.go(RouteConstants.exerciseSelection),
                  child: Text(s.againBtn),
                ),
              ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              // ── Sync Badge Indicator ──────────────────────────────────
              _SyncStatusBadge(
                isHistory: isHistory,
                isSynced: isSynced,
                syncStateAsync: syncStateAsync,
              ),
              const SizedBox(height: 12),

              ScaleTransition(
                scale: _scaleAnim,
                child: _ScoreCard(
                  score: score,
                  scoreColor: scoreColor,
                  exerciseName: exerciseName,
                  strings: s,
                ),
              ),
              if (targetReps > 0) ...[
                const SizedBox(height: 16),
                _AchievementCard(
                  achievement: achievement,
                  correctReps: correctReps,
                  targetReps: targetReps,
                  strings: s,
                ),
              ],
              const SizedBox(height: 24),
              _StatsRow(
                totalReps: totalReps,
                correctReps: correctReps,
                incorrectReps: incorrectReps,
                accuracy: accuracy,
                duration: duration,
                strings: s,
              ),
              const SizedBox(height: 24),
              _VideoReplaySection(
                showReplay: _showReplay,
                vpReady: _vpReady,
                vpCtrl: _vpCtrl,
                strings: s,
                onToggle: () {
                  setState(() => _showReplay = !_showReplay);
                  if (_showReplay && _vpCtrl == null) {
                    _initVideoPlayer();
                  } else if (_showReplay) {
                    _vpCtrl?.play();
                  } else {
                    _vpCtrl?.pause();
                  }
                },
              ),
              const SizedBox(height: 24),
              if (feedbacks.isNotEmpty) ...[
                _FeedbackSection(feedbacks: feedbacks, strings: s),
                const SizedBox(height: 24),
              ],
              if (isHistory) ...[
                OutlinedButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(s.back),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: () =>
                      context.go(RouteConstants.exerciseSelection),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(s.startNewWorkout),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.go(RouteConstants.home),
                  icon: const Icon(Icons.home_outlined),
                  label: Text(s.backToHome),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sync Status Badge Widget ───────────────────────────────────────────────
class _SyncStatusBadge extends StatelessWidget {
  const _SyncStatusBadge({
    required this.isHistory,
    required this.isSynced,
    required this.syncStateAsync,
  });

  final bool isHistory;
  final bool isSynced;
  final AsyncValue<SyncState> syncStateAsync;

  @override
  Widget build(BuildContext context) {
    if (isHistory) return const SizedBox.shrink();

    return syncStateAsync.when(
      data: (syncState) {
        final synced = isSynced || syncState.pendingCount == 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: synced
                ? AppColors.success.withValues(alpha: 0.1)
                : AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: synced ? AppColors.success : AppColors.warning,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                synced ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
                size: 16,
                color: synced ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Text(
                synced
                    ? 'Synced to Spring Boot Server (On-Device Metadata)'
                    : 'Saved Offline (Pending Sync Queue: ${syncState.pendingCount})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: synced ? AppColors.success : AppColors.warning,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ── Score Card ─────────────────────────────────────────────────────────────
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.score,
    required this.scoreColor,
    required this.exerciseName,
    required this.strings,
  });
  final double score;
  final Color scoreColor;
  final String exerciseName;
  final dynamic strings;

  String _label(dynamic s) {
    if (score >= 90) return s.excellent;
    if (score >= 75) return s.greatJob;
    if (score >= 60) return s.keepGoing;
    return s.roomToImprove;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = strings;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: scoreColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scoreColor.withValues(alpha: 0.12),
              border: Border.all(color: scoreColor, width: 2.5),
            ),
            child: Icon(
              score >= 75
                  ? Icons.emoji_events_rounded
                  : Icons.fitness_center_rounded,
              color: scoreColor,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _label(s),
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            exerciseName,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                score.toStringAsFixed(0),
                style: TextStyle(
                  color: scoreColor,
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ 100',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            s.postureScore,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Row ──────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.totalReps,
    required this.correctReps,
    required this.incorrectReps,
    required this.accuracy,
    required this.duration,
    required this.strings,
  });
  final int totalReps;
  final int correctReps;
  final int incorrectReps;
  final int accuracy;
  final String duration;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Row(
      children: [
        Expanded(
            child: _StatTile(
                value: '$totalReps',
                label: s.totalReps,
                icon: Icons.loop_rounded,
                color: AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(
            child: _StatTile(
                value: '$correctReps',
                label: s.correct,
                icon: Icons.check_circle_outline,
                color: AppColors.success)),
        const SizedBox(width: 10),
        Expanded(
            child: _StatTile(
                value: '$accuracy%',
                label: s.accuracy,
                icon: Icons.star_outline_rounded,
                color: AppColors.warning)),
        const SizedBox(width: 10),
        Expanded(
            child: _StatTile(
                value: duration,
                label: s.time,
                icon: Icons.timer_outlined,
                color: AppColors.info)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Video Replay ───────────────────────────────────────────────────────────
class _VideoReplaySection extends StatelessWidget {
  const _VideoReplaySection({
    required this.showReplay,
    required this.vpReady,
    required this.vpCtrl,
    required this.strings,
    required this.onToggle,
  });
  final bool showReplay;
  final bool vpReady;
  final VideoPlayerController? vpCtrl;
  final dynamic strings;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = strings;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.videocam_outlined,
                  color: AppColors.secondary, size: 20),
            ),
            title: Text(s.workoutReplay,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(s.reviewForm,
                style: const TextStyle(fontSize: 12)),
            trailing: TextButton(
              onPressed: onToggle,
              child: Text(showReplay ? s.hide : s.view),
            ),
          ),
          if (showReplay)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: vpReady && vpCtrl != null
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(vpCtrl!),
                          GestureDetector(
                            onTap: () {
                              vpCtrl!.value.isPlaying
                                  ? vpCtrl!.pause()
                                  : vpCtrl!.play();
                            },
                            child: Container(
                              color: Colors.transparent,
                              child: ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: vpCtrl!,
                                builder: (_, value, __) =>
                                    value.isPlaying
                                        ? const SizedBox()
                                        : const Icon(
                                            Icons.play_circle_fill_rounded,
                                            color: Colors.white70,
                                            size: 56,
                                          ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        color: const Color(0xFF0A0E1A),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                                Icons.play_circle_outline_rounded,
                                color: Colors.white38,
                                size: 56),
                            const SizedBox(height: 8),
                            Text(
                              vpCtrl == null
                                  ? s.view
                                  : s.loadingReplay,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Achievement Card ───────────────────────────────────────────────────────
class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.achievement,
    required this.correctReps,
    required this.targetReps,
    required this.strings,
  });
  final int achievement;
  final int correctReps;
  final int targetReps;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = strings;

    final color = achievement >= 90
        ? AppColors.scoreExcellent
        : achievement >= 75
            ? AppColors.scoreGood
            : achievement >= 50
                ? AppColors.scoreFair
                : AppColors.scorePoor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                s.locale == 'ko' ? '목표 달성률' : 'Goal Achievement',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '$correctReps / $targetReps ${s.reps}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: achievement / 100,
                    backgroundColor: color.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 10,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$achievement%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Feedback Section ───────────────────────────────────────────────────────
class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection(
      {required this.feedbacks, required this.strings});
  final List<String> feedbacks;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = strings;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.trainerFeedback,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...feedbacks.take(5).map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(f,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
