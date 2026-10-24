import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../data/deep_analysis_queue.dart';
import '../data/deep_analysis_service.dart';
import '../data/kori_feedback_lines.dart';

class DeepAnalysisReportScreen extends ConsumerStatefulWidget {
  const DeepAnalysisReportScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<DeepAnalysisReportScreen> createState() =>
      _DeepAnalysisReportScreenState();
}

class _DeepAnalysisReportScreenState
    extends ConsumerState<DeepAnalysisReportScreen>
    with WidgetsBindingObserver {
  final _cancel = CancelToken();
  VideoPlayerController? _video;
  Map<String, dynamic>? _result;
  Timer? _refresh;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_load);
    // 오래 열어 둬도 1시간짜리 URL을 만료 전에 교체한다.
    _refresh = Timer.periodic(const Duration(minutes: 50), (_) => _load());
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    setState(() => _loading = true);
    VideoPlayerController? next;
    try {
      final service = ref.read(deepAnalysisServiceProvider);
      final job = await service.fetchJob(widget.jobId, _cancel);
      if (!mounted || job.status != 'done') return;
      next = VideoPlayerController.networkUrl(service.videoUri(job.result!));
      await next.initialize();
      if (!mounted) return;
      final previous = _video;
      await next.seekTo(previous?.value.position ?? Duration.zero);
      if (previous?.value.isPlaying == true) await next.play();
      if (!mounted) return;
      setState(() {
        _video = next;
        _result = job.result;
      });
      next = null;
      await previous?.dispose();
    } catch (_) {
      // 연결 오류는 재생 영역의 다시 불러오기로 처리한다.
    } finally {
      await next?.dispose();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
    if (state == AppLifecycleState.paused) unawaited(_video?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    _cancel.cancel();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final share = await showModalBottomSheet<bool>(
        context: context,
        builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('사진에 저장'),
                    onTap: () => Navigator.pop(context, false)),
                ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: const Text('공유하기'),
                    onTap: () => Navigator.pop(context, true)),
              ]),
            ));
    if (share == null || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _saving = true);
    File? file;
    try {
      if (!share && !await Gal.hasAccess() && !await Gal.requestAccess()) {
        return;
      }
      file = await ref
          .read(deepAnalysisServiceProvider)
          .downloadVideo(widget.jobId, _cancel);
      if (!mounted) return;
      if (share) {
        await Share.shareXFiles([XFile(file.path, mimeType: 'video/mp4')],
            sharePositionOrigin: origin);
      } else {
        await Gal.putVideo(file.path);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('영상을 저장했어!')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('저장을 다시 시도해 줘.')));
      }
    } finally {
      try {
        await file?.parent.delete(recursive: true);
      } catch (_) {/* 임시 파일 정리 */}
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.black,
        appBar: AppBar(title: const Text('코리의 심층분석')),
        body: _result != null && _video != null
            ? DeepAnalysisReport(
                report: (_result!['report'] as Map).cast<String, dynamic>(),
                video: _VideoControls(controller: _video!),
                onSeek: (time) async {
                  await _video!.seekTo(time);
                  await _video!.play();
                },
                onDownload: _saving ? null : _download,
                downloading: _saving)
            : Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: _load, child: const Text('영상 다시 불러오기'))),
      );
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) =>
            Column(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .48),
              child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: VideoPlayer(controller))),
          VideoProgressIndicator(controller,
              allowScrubbing: true, padding: const EdgeInsets.all(12)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                tooltip: value.isPlaying ? '일시정지' : '재생',
                onPressed: value.isPlaying ? controller.pause : controller.play,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow)),
            Text(
                '${_timestamp(value.position.inMilliseconds / 1000)} / ${_timestamp(value.duration.inMilliseconds / 1000)}'),
          ]),
        ]),
      );
}

String _timestamp(num seconds) {
  final total = seconds.floor();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// 실제 플레이어와 같은 seek 콜백을 합성 리포트에서도 검증한다.
class DeepAnalysisReport extends StatelessWidget {
  const DeepAnalysisReport(
      {super.key,
      required this.report,
      required this.video,
      required this.onSeek,
      this.onDownload,
      this.downloading = false});
  final Map<String, dynamic> report;
  final Widget video;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onDownload;
  final bool downloading;

  @override
  Widget build(BuildContext context) => Column(children: [
        video,
        Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: onDownload,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(downloading ? '영상 준비 중…' : '영상 저장 · 공유'))),
              for (final item in report['timeline'] as List? ?? [])
                _timelineItem(item as Map),
              for (final rep in report['reps'] as List? ?? [])
                _metrics(rep as Map),
              for (final note in report['notes'] as List? ?? [])
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('$note',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white60))),
            ])),
      ]);

  Widget _timelineItem(Map item) {
    final color = switch (item['severity']) {
      'critical' || 'error' => Colors.redAccent,
      'warning' => Colors.amber,
      _ => Colors.lightBlueAccent,
    };
    final seconds = item['t'] as num;
    return Card(
        child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Text(_timestamp(seconds),
          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      title: Text('${item['title']}',
          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      subtitle:
          Text('${item['body']}', maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => onSeek(Duration(milliseconds: (seconds * 1000).round())),
    ));
  }

  Widget _metrics(Map rep) {
    final angles = rep['anglesDeg'] as Map;
    final tempo = rep['tempoSeconds'] as Map;
    final path = rep['handPath'] as Map;
    final trunk = rep['trunkStability'] as Map;
    final deviceNotes = (rep['onDeviceWarnings'] as List? ?? [])
        .map((key) =>
            koriFeedbackLines[key]?.render(isKo: true) ?? '다른 자세 메모가 있어.')
        .join(' · ');
    final comparison = switch (rep['comparison']) {
      'agree' => '비교한 항목은 기기와 같아',
      'different' => '기기와 다른 소견이 있어',
      _ => '직접 비교할 항목은 없어',
    };
    return ExpansionTile(
        title: Text('${rep['repIndex']}회 · 자세히 보기'),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Text(
              'ROM ${rep['romDeg']}° · 깊이 최소각 ${rep['depthAngleDeg']}° · 골반 높이 변화 ${rep['depthMeters']}m'),
          for (final entry in const {
            'knee': '무릎',
            'hip': '고관절',
            'elbow': '팔꿈치',
            'shoulder': '어깨',
            'torso': '몸통(중력 기준)'
          }.entries)
            Text(
                '${entry.value} · 위 ${angles[entry.key]['top']}° / 아래 ${angles[entry.key]['bottom']}°'),
          Text(
              '늘림 ${tempo['eccentric']}초 · 멈춤 ${tempo['pause']}초 · 수축 ${tempo['concentric']}초'),
          Text(
              '손목 경로 ${path['length']}m · 수평 이동 ${path['horizontalExcursion']}m'),
          Text(
              '몸통 흔들림 ${trunk['stdDeg']}° · 좌우 최대 차이 ${rep['symmetryDeg'][rep['primaryJoint']]['max']}°'),
          if (rep['fatigueDrift']['comparable'] == true)
            Text('첫 3회 대비 ROM 감소 ${rep['fatigueDrift']['romDropDeg']}°'),
          Text('기기 메모: ${deviceNotes.isEmpty ? '별도 경고는 없었어.' : deviceNotes}'),
          Text(
              '$comparison · 검출 지지도 ${((rep['confidence'] as num) * 100).round()}%'),
          if ((rep['unassessedDeviceWarnings'] as List? ?? []).isNotEmpty)
            const Text('기기 경고 중 아직 비교하지 못한 항목이 있어.'),
          for (final fault in rep['faults'] as List? ?? [])
            TextButton(
                onPressed: () => onSeek(Duration(
                    milliseconds:
                        ((fault['evidence'][0]['t'] as num) * 1000).round())),
                child: Text(
                    '${fault['title']} · 근거 보기 (${((fault['confidence'] as num) * 100).round()}%)')),
        ]);
  }
}

class DeepAnalysisStatus extends ConsumerWidget {
  const DeepAnalysisStatus(
      {super.key, this.sessionId, this.recordId, this.label});
  final String? sessionId;
  final String? recordId;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref
        .watch(deepAnalysisQueueProvider)
        .values
        .where((row) => sessionId != null
            ? row['sessionId'] == sessionId
            : recordId != null && row['recordId'] == recordId)
        .toList();
    final visible = rows.where((row) => row['status'] != 'failed').toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final done = visible.every((row) => row['status'] == 'done');
    return TextButton(
      onPressed: done && visible.length == 1
          ? () async {
              final landscape =
                  MediaQuery.orientationOf(context) == Orientation.landscape;
              await SystemChrome.setPreferredOrientations(
                  [DeviceOrientation.portraitUp]);
              if (!context.mounted) return;
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => DeepAnalysisReportScreen(
                      jobId: visible.single['jobId'] as String)));
              if (landscape && context.mounted) {
                await SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight
                ]);
              }
            }
          : null,
      child: Text(
          '${label == null ? '' : '$label · '}${done ? '완료' : '심층분석 중…'}',
          style: TextStyle(
              fontSize: 12,
              color: done ? Colors.lightGreenAccent : Colors.white70)),
    );
  }
}

class DeepAnalysisSection extends ConsumerWidget {
  const DeepAnalysisSection({super.key, required this.recordId});
  final String? recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref
        .watch(deepAnalysisQueueProvider)
        .values
        .where((row) => recordId != null && row['recordId'] == recordId)
        .toList()
      ..sort(
          (a, b) => (a['setNumber'] as int).compareTo(b['setNumber'] as int));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final row in rows)
        DeepAnalysisStatus(
            sessionId: row['sessionId'] as String,
            label: '${row['setNumber']}세트 심층분석'),
    ]);
  }
}
