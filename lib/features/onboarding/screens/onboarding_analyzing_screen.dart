import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../demo/demo_autopilot.dart';
import '../services/calibration_result_store.dart';
import '../models/body_analysis_result.dart';
import '../services/calibration_upload_service.dart';
import '../widgets/body_mesh_reveal.dart';

/// Shown right after the 4 body-scan photos are captured. Uploads the capture
/// bundle on its own (no button), plays the analysis progress animation, then
/// prepares the result during the existing wait when the mesh flag is enabled.
/// Missing or failed analysis never blocks continuing to the result.
class OnboardingAnalyzingScreen extends ConsumerStatefulWidget {
  const OnboardingAnalyzingScreen({super.key, this.sessionPath});

  /// `Documents/calibration/<sessionId>` written by the native calibration session.
  final String? sessionPath;

  @override
  ConsumerState<OnboardingAnalyzingScreen> createState() =>
      _OnboardingAnalyzingScreenState();
}

class _OnboardingAnalyzingScreenState
    extends ConsumerState<OnboardingAnalyzingScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(seconds: 40);

  late final AnimationController _controller;

  /// Settles (never throws) when the upload has finished, failed or was skipped.
  late final Future<void> _upload;
  late final Future<void> _analysis;
  final _cancel = CancelToken();
  BodyAnalysisResult _result = const BodyAnalysisResult();
  bool _finished = false;

  /// Accepted fit job, for the 3D body reveal ([kBodyMeshReveal]).
  String? _jobId;

  @override
  void initState() {
    super.initState();
    _upload = _startUpload();
    _analysis = kBodyMeshReveal ? _prepareResult() : _upload;
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finishAfterUpload();
      })
      ..forward();
  }

  /// Sends the 4 photos + metadata right away. Keeps running if the user
  /// leaves the screen, so the bundle still reaches the server.
  Future<void> _startUpload() async {
    final path = widget.sessionPath;
    final service = ref.read(calibrationUploadServiceProvider);
    final issue = service.config.configurationIssue;
    if (path == null || path.isEmpty) {
      debugPrint('[Calibration] 촬영 데이터 없음 → 전송 건너뜀');
      return;
    }
    if (issue != null) {
      debugPrint('[Calibration] 전송 건너뜀: $issue');
      return;
    }
    try {
      debugPrint('[Calibration] 사진 4장 자동 전송 시작');
      final receipt = await service.upload(path, cancelToken: CancelToken());
      _jobId = receipt.jobId;
      debugPrint('[Calibration] 전송·접수 완료 (접수 번호 ${receipt.jobId})');
      if (CalibrationResultStore.enabled) unawaited(CalibrationResultStore.instance.track(service, receipt.jobId));
    } on CalibrationUploadException catch (error) {
      debugPrint('[Calibration] 전송 실패: ${error.message}');
    } on DioException catch (error) {
      debugPrint('[Calibration] 전송 실패: ${error.type.name}');
    } catch (_) {
      // Never log transport exceptions: they can contain signed URLs/credentials.
      debugPrint('[Calibration] 전송 실패');
    }
  }

  Future<void> _finishAfterUpload() async {
    await _analysis;
    _finish();
  }

  Future<void> _prepareResult() async {
    await _upload;
    final jobId = _jobId;
    if (!mounted || _finished || jobId == null) return;
    final service = ref.read(calibrationUploadServiceProvider);
    // TRIAL BRANCH ONLY: the demo autopilot waits up to 7 min (a cold GPU start took longer than 3).
    final started = DateTime.now();
    final limit = DemoAutopilot.active ? const Duration(minutes: 7) : const Duration(minutes: 3);
    final timeout = Timer(limit, () => _cancel.cancel());
    try {
      while (mounted && !_finished && !_cancel.isCancelled) {
        CalibrationJob job;
        try {
          job = await service.fetchJob(jobId, cancelToken: _cancel);
        } on CalibrationUploadException catch (error) {
          DemoAutopilot.logJob(jobId, started, error: 'poll: ${error.message}');
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
        DemoAutopilot.logJob(jobId, started, job: job);
        if (job.status == 'failed') return;
        if (job.status == 'done') {
          final values = job.result ?? const <String, dynamic>{};
          _result = BodyAnalysisResult(values: values);
          final url = values['modelGlbUrl'];
          if (url is! String || url.isEmpty) return;
          final glb = await service.fetchModel(url, cancelToken: _cancel);
          DemoAutopilot.logJob(jobId, started, error: 'glb ${glb.length} bytes');
          final meshId = await BodyMeshReveal.prepare(glb);
          DemoAutopilot.logJob(jobId, started, error: 'mesh prepared ${meshId != null}');
          if (!mounted || _finished || _cancel.isCancelled) {
            await BodyMeshReveal.release(meshId);
            return;
          }
          _result = BodyAnalysisResult(values: values, meshId: meshId);
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    } catch (error) {
      DemoAutopilot.logJob(jobId, started, error: 'stopped: ${error.runtimeType}');
      // Preserve the summary on download/parse failure; never log signed URLs.
      debugPrint('[BodyMesh] 미리보기 없이 분석 결과 표시');
    } finally {
      timeout.cancel();
    }
  }

  void _finish() {
    // The capture bundle stays on disk so a failed upload can be sent again later.
    if (!mounted || _finished) return;
    _finished = true;
    context.go(RouteConstants.onboardingResult,
        extra: kBodyMeshReveal ? _result : null);
  }

  // TODO(temp): debug-only skip button — the analysis is still a fake
  // 40s animation, so this jumps straight to the result screen for testing.
  void _debugSkip() {
    _controller.stop();
    _finish();
  }

  @override
  void dispose() {
    _cancel.cancel();
    if (!_finished) BodyMeshReveal.release(_result.meshId);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Pretendard'),
        scaffoldBackgroundColor: AppColors.black,
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: Stack(
          children: [
            SafeArea(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final progress = _controller.value;
                  final percent = (progress * 100).floor().clamp(0, 100);
                  final keypointsDone = progress >= 1 / 3;
                  final modelDone = progress >= 2 / 3;
                  final bonesDone = progress >= 1.0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        SizedBox(
                          width: 220,
                          height: 220,
                          child: CustomPaint(
                            painter: _ProgressRingPainter(progress: progress),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '$percent',
                                          style: const TextStyle(
                                              color: AppColors.white,
                                              fontSize: 44,
                                              fontWeight: FontWeight.w900),
                                        ),
                                        const TextSpan(
                                          text: '%',
                                          style: TextStyle(
                                              color: AppColors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text('분석 중',
                                      style: TextStyle(
                                          color: Color(0xFF9AA0A6),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Spacer(flex: 1),
                        const Text('체형 분석 중이야!\n금방 끝나',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.white,
                                fontSize: 24,
                                height: 1.25,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 22),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.purple,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/images/character/face.png',
                                width: 44,
                                height: 48,
                                fit: BoxFit.contain,
                                excludeFromSemantics: true,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text('40초 정도 걸려.\n조금만 기다려줘!',
                                    style: TextStyle(
                                        color: AppColors.black,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        height: 1.35)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _StepRow(
                          label: '관절 키포인트 추출',
                          state: keypointsDone
                              ? _StepState.done
                              : _StepState.active,
                        ),
                        const SizedBox(height: 10),
                        _StepRow(
                          label: '3D 체형 만들기',
                          state: modelDone
                              ? _StepState.done
                              : keypointsDone
                                  ? _StepState.active
                                  : _StepState.waiting,
                        ),
                        const SizedBox(height: 10),
                        _StepRow(
                          label: '뼈 길이 추출',
                          state: bonesDone
                              ? _StepState.done
                              : modelDone
                                  ? _StepState.active
                                  : _StepState.waiting,
                        ),
                        const Spacer(flex: 1),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('사진은 분석 끝나면 바로 지울게',
                              style: TextStyle(
                                  color: Color(0xFF6B6B6B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // TODO(temp): debug-only skip button — remove once the real
            // analysis pipeline is wired up.
            if (kDebugMode)
              Positioned(
                right: 16,
                bottom: 100,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: _debugSkip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.red, width: 1.5),
                      ),
                      child: const Text('결과 보기 (테스트용)',
                          style: TextStyle(
                              color: AppColors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _StepState { done, active, waiting }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final isActive = state == _StepState.active;
    final isDone = state == _StepState.done;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isActive ? AppColors.green : Colors.transparent, width: 1.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: isDone
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                        color: AppColors.green, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded,
                        color: AppColors.black, size: 15),
                  )
                : isActive
                    ? const CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(AppColors.green),
                      )
                    : const DecoratedBox(
                        decoration: BoxDecoration(
                            color: Color(0xFF2B2B2B), shape: BoxShape.circle),
                      ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: isActive || isDone
                        ? AppColors.white
                        : const Color(0xFF6B6B6B),
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          Text(
            isDone ? '완료' : (isActive ? '진행 중' : '대기 중'),
            style: TextStyle(
                color: isDone
                    ? const Color(0xFF9AA0A6)
                    : isActive
                        ? AppColors.green
                        : const Color(0xFF6B6B6B),
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Circular progress ring with a dark-to-bright green sweep, matching the
/// analyzing screen mockup.
class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({required this.progress});
  final double progress;

  static const _strokeWidth = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = const Color(0xFF262626)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: const [Color(0xFF4E6B1F), AppColors.green],
        stops: [0, progress.clamp(0.001, 1.0)],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);

    canvas.drawArc(rect, -math.pi / 2, progress * 2 * math.pi, false, sweep);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
