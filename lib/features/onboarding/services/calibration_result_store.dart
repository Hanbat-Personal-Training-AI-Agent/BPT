import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calibration_upload_service.dart';

/// 실험용 개인화 준비 자세(ai/setup-constraint) — `--dart-define=BPT_EXERCISE_SETUP=true` 일 때만 동작한다(기본 꺼짐).
///
/// 체형 캘리브레이션 `done` 결과(SMPL β, boneLengthData cm, 키)를 받아 이 기기에 저장하고, 운동 준비 자세 화면에
/// 관절 중심 기준 체형 치수(골반·어깨 너비, 팔·다리 길이)를 넘긴다. 이 치수는 "참고 표시"용이다 — 화면의 발/손 간격은
/// 같은 프레임 3D의 비율로 재고, cm 측정값인 것처럼 보이지 않는다. 사용자가 저장한 "내 기준"(운동·변형별 항목 값)도 둔다.
/// GLB 주소(1시간 만료)는 저장하지 않는다. 주소·토큰은 로그에 남기지 않는다.
class CalibrationResultStore {
  CalibrationResultStore._();

  static final instance = CalibrationResultStore._();

  static const bool enabled = bool.fromEnvironment('BPT_EXERCISE_SETUP');

  static const resultKey = 'bpt_calibration_result_v1';
  static String referenceKey(String exerciseId, String variant) => 'bpt_setup_reference_v1_${exerciseId}_$variant';

  /// `fetchJob` 를 [interval] 마다 불러 done/failed 가 오면 멈춘다([timeout] 뒤 포기). done 이면 저장한다. 예외를 던지지 않는다.
  Future<void> track(CalibrationUploadService service, String jobId,
      {Duration interval = const Duration(seconds: 3), Duration timeout = const Duration(minutes: 3)}) async {
    if (!enabled) return;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final job = await service.fetchJob(jobId);
        if (job.status == 'done' && job.result != null) {
          await save(jobId, job.result!);
          debugPrint('[Calibration] 체형 결과 저장');
          return;
        }
        if (job.status == 'failed') {
          debugPrint('[Calibration] 체형 분석 실패: ${job.error}');
          return;
        }
      } catch (_) {
        // 네트워크·토큰 오류는 다음 조회에서 다시 시도한다 (예외 내용은 주소를 담을 수 있어 남기지 않음).
      }
      await Future<void>.delayed(interval);
    }
    debugPrint('[Calibration] 체형 결과 대기 시간 초과');
  }

  /// done 결과에서 앱이 쓰는 필드만 저장 (GLB 주소·debug 제외).
  Future<void> save(String jobId, Map<String, dynamic> result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      resultKey,
      jsonEncode({
        'jobId': jobId,
        'userHeightCm': result['userHeightCm'],
        'smplBeta': result['smplBeta'],
        'boneLengthData': result['boneLengthData'],
        'calibratedAt': result['calibratedAt'],
      }),
    );
  }

  Future<Map<String, dynamic>?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(resultKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, double>?> bodyProfile() async => bodyProfileFrom(await load());

  /// 저장된 결과 → {hipWidthCm, shoulderWidthCm, thighCm, shinCm, upperArmCm, forearmCm, heightCm} (좌우 평균, 관절 중심 기준).
  /// 결과가 없거나 너비가 없으면 null.
  static Map<String, double>? bodyProfileFrom(Map<String, dynamic>? result) {
    final segments = (result?['boneLengthData'] as Map?)?['segments'];
    if (segments is! Map) return null;
    double? seg(String name) {
      final v = segments[name];
      return v is num && v.isFinite && v > 0 ? v.toDouble() : null;
    }

    double? mean(String right, String left) {
      final r = seg(right), l = seg(left);
      if (r == null && l == null) return null;
      if (r == null || l == null) return r ?? l;
      return (r + l) / 2;
    }

    final hip = seg('hip_width'), shoulder = seg('shoulder_width');
    if (hip == null && shoulder == null) return null;
    final height = result?['userHeightCm'];
    final out = <String, double?>{
      'hipWidthCm': hip,
      'shoulderWidthCm': shoulder,
      'thighCm': mean('right_hip-right_knee', 'left_hip-left_knee'),
      'shinCm': mean('right_knee-right_ankle', 'left_knee-left_ankle'),
      'upperArmCm': mean('right_shoulder-right_elbow', 'left_shoulder-left_elbow'),
      'forearmCm': mean('right_elbow-right_wrist', 'left_elbow-left_wrist'),
      'heightCm': height is num && height > 0 ? height.toDouble() : null,
    };
    return {
      for (final e in out.entries)
        if (e.value != null) e.key: e.value!,
    };
  }

  /// 사용자가 저장한 내 기준 (운동·변형별 항목 값). 없으면 빈 맵.
  Future<Map<String, double>> loadReference(String exerciseId, String variant) async {
    final raw = (await SharedPreferences.getInstance()).getString(referenceKey(exerciseId, variant));
    if (raw == null) return {};
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return {};
      return {
        for (final e in value.entries)
          if (e.key is String && e.value is num) e.key as String: (e.value as num).toDouble(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveReference(String exerciseId, String variant, Map<String, double> values) async {
    await (await SharedPreferences.getInstance()).setString(referenceKey(exerciseId, variant), jsonEncode(values));
  }
}
