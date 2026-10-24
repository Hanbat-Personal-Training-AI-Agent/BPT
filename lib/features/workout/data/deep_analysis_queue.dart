import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'deep_analysis_service.dart';

/// 화면 수명과 분리된 계정별 대기열. 앱 재실행·복귀 시 저장한 작업을 이어 간다.
class DeepAnalysisQueue extends StateNotifier<Map<String, Map<String, dynamic>>>
    with WidgetsBindingObserver {
  DeepAnalysisQueue(this.service, {this.interval = const Duration(seconds: 5)})
      : super({}) {
    WidgetsBinding.instance.addObserver(this);
    ready = _restore();
  }

  final DeepAnalysisService service;
  final Duration interval;
  late final Future<void> ready;
  final _cancel = CancelToken();
  Timer? _timer;
  bool _working = false;
  Future<void> _saving = Future.value();

  Future<void> _restore() async {
    try {
      final rows = await service.loadQueue();
      if (!mounted) return;
      state = {
        for (final row in rows)
          if (row['sessionId'] is String)
            row['sessionId'] as String: {
              ...row,
              'status': row['status'] ?? 'queued'
            }
      };
    } catch (_) {
      // 손상된 로컬 캐시가 운동 흐름을 막지 않는다.
    }
    if (!mounted) return;
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
    unawaited(tick());
  }

  Future<void> _persist() {
    final rows =
        state.values.map((row) => Map<String, dynamic>.from(row)).toList();
    _saving =
        _saving.catchError((Object _) {}).then((_) => service.saveQueue(rows));
    return _saving;
  }

  Future<void> enqueueSet(Map record, String exerciseId,
      {required String recordId}) async {
    final capture = DeepAnalysisCapture.fromSet(record, exerciseId);
    if (capture == null) return;
    await ready;
    if (!mounted || state.containsKey(capture.sessionId)) return;
    state = {
      ...state,
      capture.sessionId: {
        'sessionId': capture.sessionId,
        'exerciseId': exerciseId,
        'recordId': recordId,
        'setNumber': record['setIndex'] ?? 1,
        'createdAt': DateTime.now().toIso8601String(),
        'videoPath': capture.videoPath,
        'manifest': capture.manifest,
        'status': 'waiting',
      }
    };
    try {
      await _persist();
      await tick();
    } catch (_) {
      // 디스크 쓰기 실패도 사용자에게 팝업을 띄우지 않는다. 다음 tick에서 재시도한다.
    }
  }

  void _update(String session, Map<String, dynamic> changes) {
    if (mounted) {
      state = {
        ...state,
        session: {...state[session]!, ...changes}
      };
    }
  }

  Future<void> tick() async {
    if (_working || !mounted || _cancel.isCancelled) return;
    _working = true;
    try {
      for (final session in state.keys.toList()) {
        if (!mounted || _cancel.isCancelled) break;
        final row = state[session]!;
        if (row['status'] == 'done' || row['status'] == 'failed') continue;
        final next = row['nextAttemptMs'] as int? ?? 0;
        if (next > DateTime.now().millisecondsSinceEpoch) continue;
        try {
          var jobId = row['jobId'] as String?;
          if (jobId == null) {
            final capture = DeepAnalysisCapture(row['videoPath'] as String,
                (row['manifest'] as Map).cast<String, dynamic>());
            if (!await service.canUpload(capture)) continue;
            _update(session, {'status': 'uploading'});
            jobId = await service.upload(capture, _cancel);
            if (!mounted) break;
            _update(session, {
              'jobId': jobId, 'status': 'queued', 'failures': 0,
              // 접수 후에는 영상 경로·반복 원문·서명 URL을 캐시에 보관하지 않는다.
              'videoPath': null, 'manifest': null
            });
            await _persist();
          }
          final job = await service.fetchJob(jobId, _cancel);
          if (!mounted) break;
          if (job.status == 'failed' && job.retryable) {
            // GPU 실패는 서버의 멱등 재접수로 한 번만 재시도한다.
            final retryId = await service.retryJob(jobId, _cancel);
            _update(
                session, {'jobId': retryId, 'status': 'queued', 'failures': 0});
          } else {
            _update(session,
                {'status': job.status, 'failures': 0, 'nextAttemptMs': 0});
          }
        } on FileSystemException {
          _update(session, {'status': 'failed'});
        } on FormatException {
          _update(session, {'status': 'failed'});
        } catch (_) {
          if (!mounted || _cancel.isCancelled) break;
          final failures = (row['failures'] as int? ?? 0) + 1;
          // 오프라인·인증·서버 연결 실패: 최대 5분 간격, 같은 세션 ID로 재접수한다.
          final delay = [30, 60, 120, 300][(failures - 1).clamp(0, 3)];
          _update(session, {
            'status': 'waiting',
            'failures': failures,
            'nextAttemptMs': DateTime.now()
                .add(Duration(seconds: delay))
                .millisecondsSinceEpoch
          });
        }
        if (mounted) await _persist();
      }
    } catch (_) {
      // 저장소 오류는 다음 주기에 다시 확인한다.
    } finally {
      _working = false;
    }
  }

  @override
  // ignore: avoid_renaming_method_parameters  -- `state` is this notifier's queue
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) unawaited(tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancel.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final deepAnalysisQueueProvider =
    StateNotifierProvider<DeepAnalysisQueue, Map<String, Map<String, dynamic>>>(
  (ref) => DeepAnalysisQueue(ref.watch(deepAnalysisServiceProvider)),
);
