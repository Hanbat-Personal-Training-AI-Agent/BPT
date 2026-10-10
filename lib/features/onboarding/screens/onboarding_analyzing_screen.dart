import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../services/calibration_upload_service.dart';

/// Upload the native four-view bundle, then poll the server's body fit.
/// Never substitute a timer or a demo body for a real server acknowledgement
/// or result: only a `done` job with a real fit counts as analysed.
class OnboardingAnalyzingScreen extends ConsumerStatefulWidget {
  const OnboardingAnalyzingScreen({super.key, this.sessionPath});

  /// Documents/calibration/<sessionId>, produced by CalibrationStore.
  final String? sessionPath;

  @override
  ConsumerState<OnboardingAnalyzingScreen> createState() =>
      _OnboardingAnalyzingScreenState();
}

class _OnboardingAnalyzingScreenState
    extends ConsumerState<OnboardingAnalyzingScreen> {
  CancelToken? _cancelToken;
  CalibrationUploadProgress? _progress;
  CalibrationUploadReceipt? _receipt;
  String? _error;
  bool _busy = false;
  CalibrationJob? _job;
  String? _jobError;
  bool _polling = false;
  static const pollInterval = Duration(seconds: 3);

  static String failureText(String? code) => switch (code) {
        'person_not_found' => '사진에서 사람을 찾지 못했어요. 전신이 보이게 다시 촬영해 주세요.',
        'low_keypoint_confidence' => '관절이 잘 보이지 않았어요. 밝은 곳에서 다시 촬영해 주세요.',
        'fit_diverged' => '체형을 맞추지 못했어요. 자세를 바르게 하고 다시 촬영해 주세요.',
        'timeout' => '분석 시간이 초과됐어요. 잠시 뒤 다시 촬영해 주세요.',
        _ => '분석 중 오류가 났어요. 잠시 뒤 다시 시도해 주세요.',
      };

  Timer? _pollTimer;

  /// One status request; schedules the next one until done/failed.
  Future<void> _poll(String jobId) async {
    if (_polling) return;
    setState(() {
      _polling = true;
      _jobError = null;
    });
    try {
      final job = await ref
          .read(calibrationUploadServiceProvider)
          .fetchJob(jobId, cancelToken: _cancelToken);
      if (!mounted) return;
      setState(() => _job = job);
      if (!job.finished) {
        _pollTimer = Timer(pollInterval, () => _poll(jobId));
      }
    } on CalibrationUploadException catch (error) {
      if (mounted) setState(() => _jobError = error.message);
    } on DioException catch (error) {
      if (mounted && !CancelToken.isCancel(error)) {
        setState(() => _jobError = '분석 상태를 확인하지 못했어요.');
      }
    } finally {
      if (mounted) setState(() => _polling = false);
    }
  }

  Future<void> _upload() async {
    final path = widget.sessionPath;
    if (_busy || path == null || path.isEmpty) return;
    final token = CancelToken();
    setState(() {
      _cancelToken = token;
      _busy = true;
      _error = null;
      _progress =
          const CalibrationUploadProgress(CalibrationUploadStage.validating);
    });
    try {
      final receipt = await ref.read(calibrationUploadServiceProvider).upload(
        path,
        cancelToken: token,
        onProgress: (progress) {
          if (mounted && !token.isCancelled) {
            setState(() => _progress = progress);
          }
        },
      );
      if (mounted) {
        setState(() => _receipt = receipt);
        _poll(receipt.jobId);
      }
    } on CalibrationUploadException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on DioException catch (error) {
      if (mounted) {
        setState(() => _error = CancelToken.isCancel(error)
            ? '전송을 중단했어요. 사진은 기기에 보관돼 있어요.'
            : '전송에 실패했어요. 다시 시도해 주세요.');
      }
    } catch (_) {
      // Never display transport exceptions containing signed URLs/credentials.
      if (mounted) setState(() => _error = '전송에 실패했어요. 사진은 기기에 보관돼 있어요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cancelToken?.cancel();
    super.dispose();
  }

  String get _stageText {
    if (_receipt != null) return '사진 전송·접수 완료';
    if (!_busy) return '사진 전송 대기';
    return switch (_progress?.stage) {
      CalibrationUploadStage.validating => '촬영 파일 확인 중',
      CalibrationUploadStage.requesting => '업로드 주소 요청 중',
      CalibrationUploadStage.uploading => '사진 전송 중',
      CalibrationUploadStage.confirming => '서버 접수 확인 중',
      CalibrationUploadStage.accepted => '사진 전송·접수 완료',
      null => '사진 전송 준비 중',
    };
  }

  @override
  Widget build(BuildContext context) {
    final issue =
        ref.watch(calibrationUploadServiceProvider).config.configurationIssue;
    final hasSession = widget.sessionPath?.isNotEmpty ?? false;
    final accepted = _receipt != null;
    final fraction = accepted ? 1.0 : (_progress?.fraction ?? 0.0);
    final sending = _progress?.stage == CalibrationUploadStage.uploading;
    return Theme(
      data: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Pretendard'),
        scaffoldBackgroundColor: AppColors.black,
      ),
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Icon(
                    accepted
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_upload_outlined,
                    color: AppColors.green,
                    size: 72),
                const SizedBox(height: 24),
                Text(_stageText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Text(
                  !accepted
                      ? '정면·양쪽 사선·뒷면 사진 4장과\n키, 관절 좌표, 카메라 정보를 전송해요.'
                      : _job?.status == 'done'
                          ? '3D 체형 분석이 끝났어요.'
                          : _job?.status == 'failed'
                              ? failureText(_job!.error)
                              : '사진과 메타데이터가 서버에 접수됐어요.\n3D 체형을 분석하고 있어요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 28),
                if (_busy || accepted) ...[
                  LinearProgressIndicator(
                    value: sending || accepted ? fraction : null,
                    color: AppColors.green,
                    backgroundColor: AppColors.grey,
                  ),
                  const SizedBox(height: 10),
                  if (sending)
                    Text('파일 전송 ${(fraction * 100).floor()}%',
                        textAlign: TextAlign.center),
                ],
                const SizedBox(height: 16),
                _UploadStep(
                    label: '자동 촬영 4장·메타데이터',
                    status: hasSession ? '기기 저장' : '촬영 필요'),
                _UploadStep(
                    label: '서버리스 저장소 전송',
                    status: accepted
                        ? '접수 완료'
                        : _busy
                            ? '진행 중'
                            : '대기'),
                _UploadStep(
                    label: '3D 체형 분석 결과',
                    status: switch (_job?.status) {
                      'queued' => '대기 중',
                      'running' => '분석 중 ${_job!.progressRate}%',
                      'done' => '완료',
                      'failed' => '실패',
                      _ => accepted ? '확인 중' : '대기',
                    }),
                if (_job?.result case final result?) ...[
                  _ResultSummary(result: result),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('show-calibration-result'),
                    onPressed: () => context.go(RouteConstants.onboardingResult,
                        extra: result),
                    child: const Text('3D 체형 결과 보기'),
                  ),
                ],
                if (_jobError != null) ...[
                  Text(_jobError!,
                      key: const Key('job-error'),
                      style: const TextStyle(color: AppColors.red)),
                  TextButton(
                    key: const Key('retry-job-status'),
                    onPressed:
                        _polling ? null : () => _poll(_receipt!.jobId),
                    child: const Text('분석 상태 다시 확인'),
                  ),
                ],
                const SizedBox(height: 16),
                if (!hasSession) const Text('촬영 데이터가 없어요. 먼저 사진 4장을 촬영해 주세요.'),
                if (issue != null)
                  Text(issue, key: const Key('upload-configuration-issue')),
                if (_error != null)
                  Text(_error!,
                      key: const Key('upload-error'),
                      style: const TextStyle(color: AppColors.red)),
                if (_receipt != null)
                  Text('접수 번호: ${_receipt!.jobId}',
                      key: const Key('upload-receipt')),
                const SizedBox(height: 20),
                if (!accepted)
                  FilledButton(
                    key: const Key('upload-calibration'),
                    onPressed:
                        !_busy && hasSession && issue == null ? _upload : null,
                    child: Text(_error == null ? '동의하고 사진 4장 전송' : '다시 전송'),
                  ),
                if (_busy)
                  TextButton(
                      onPressed: () => _cancelToken?.cancel(),
                      child: const Text('전송 중단')),
                const SizedBox(height: 12),
                const Text(
                  '전송 버튼을 누르면 체형 분석을 위해 촬영 자료를 업로드해요. '
                  '사진은 재시도를 위해 기기에 유지돼요. '
                  '서버 보관·삭제 정책과 분석 결과 연결은 서비스 운영 전 확정해야 해요.',
                  style: TextStyle(
                      color: Color(0xFF9AA0A6), fontSize: 12, height: 1.5),
                ),
                TextButton(
                  key: const Key('continue-without-analysis'),
                  onPressed:
                      _busy ? null : () => context.go(RouteConstants.home),
                  child: const Text('체형 분석 없이 홈으로 가기'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.go(RouteConstants.onboardingCapture),
                  child: const Text('촬영 안내로 돌아가기'),
                ),
                if (kDebugMode)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => context.go(RouteConstants.onboardingResult),
                    child: const Text('데모 결과 보기 (실제 분석 아님)'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Height and the leg/arm lengths the app's 3D checks use, from the real result.
class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final segments = (result['boneLengthData'] as Map)['segments'];
    String cm(String a, String b) {
      final values = [segments?[a], segments?[b]].whereType<num>();
      return values.isEmpty
          ? '-'
          : (values.reduce((x, y) => x + y) / values.length).toStringAsFixed(1);
    }

    final comment = result['coachComment'];
    return Column(
      key: const Key('calibration-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('키 ${result['userHeightCm']}cm 기준 · 허벅지 '
            '${cm('right_hip-right_knee', 'left_hip-left_knee')}cm · 정강이 '
            '${cm('right_knee-right_ankle', 'left_knee-left_ankle')}cm · 위팔 '
            '${cm('right_shoulder-right_elbow', 'left_shoulder-left_elbow')}cm'),
        if (comment is String && comment.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(comment, style: const TextStyle(color: AppColors.green)),
        ],
      ],
    );
  }
}

class _UploadStep extends StatelessWidget {
  const _UploadStep({required this.label, required this.status});
  final String label;
  final String status;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(status, style: const TextStyle(color: AppColors.green)),
        ]),
      );
}
