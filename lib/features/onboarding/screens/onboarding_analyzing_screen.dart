import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../services/calibration_upload_service.dart';

/// Upload the native four-view bundle; analysis results are not connected yet.
/// Never substitute a timer or a demo body for a real server acknowledgement.
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
      if (mounted) setState(() => _receipt = receipt);
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
                  accepted
                      ? '사진과 메타데이터가 서버에 접수됐어요.\n3D 체형 분석 결과 연동은 아직 준비 중이에요.'
                      : '정면·양쪽 사선·뒷면 사진 4장과\n키, 관절 좌표, 카메라 정보를 전송해요.',
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
                const _UploadStep(label: '3D 체형 분석 결과', status: '미연결'),
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
