import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/native_pose_channel.dart';

/// 실험용 개인화 준비 자세 패널 (`--dart-define=BPT_EXERCISE_SETUP=true` 일 때만 운동 화면에 뜬다).
///
/// 보여 주는 것: 운동(스쿼트는 변형), 체형 캘리브레이션의 관절 중심 너비(cm, 참고 표시), 각 항목의 현재 비율(같은 프레임의
/// 골반·어깨 관절 너비에 대한 배수), 관측 품질, 준비 상태, 그리고 사용자가 저장한 "내 기준"이 있을 때만 조정 안내.
/// 하지 않는 것: 내장된 "이상적인 간격"과 비교하기, 관측이 부족할 때 숫자 보이기, 안정된 관측을 "올바른 자세"라고 말하기.
class ExerciseSetupPanel extends StatelessWidget {
  const ExerciseSetupPanel({
    super.key,
    required this.isKo,
    required this.exerciseId,
    required this.exerciseName,
    this.status,
    this.variant = 'bodyweight',
    this.bodyProfile,
    this.hasReference = false,
    this.onVariantChanged,
    this.onReset,
    this.onSaveReference,
    this.onDismiss,
  });

  final bool isKo;
  final String exerciseId;
  final String exerciseName;
  final NativeSetupStatus? status;
  final String variant;

  /// CalibrationResultStore.bodyProfile (cm, 관절 중심). null = 캘리브레이션 결과 없음.
  final Map<String, double>? bodyProfile;
  final bool hasReference;
  final ValueChanged<String>? onVariantChanged;
  final VoidCallback? onReset;
  final VoidCallback? onSaveReference;
  final VoidCallback? onDismiss;

  /// 스쿼트 변형: 내 기준을 따로 저장하는 표시일 뿐, 변형별 고정 제약은 없다.
  static const squatVariants = ['bodyweight', 'back_squat', 'front_squat'];

  static String variantLabel(String v, {required bool isKo}) => switch (v) {
        'back_squat' => isKo ? '백스쿼트' : 'Back squat',
        'front_squat' => isKo ? '프런트스쿼트' : 'Front squat',
        _ => isKo ? '맨몸' : 'Bodyweight',
      };

  static String itemLabel(NativeSetupItem item, {required bool isKo}) => switch (item.key) {
        'feet_width' => isKo ? '발 간격' : 'Feet width',
        'feet_width_shoulder' => isKo ? '발 간격(어깨 기준)' : 'Feet width (shoulders)',
        'foot_symmetry' => isKo ? '발 좌우 치우침' : 'Feet left/right offset',
        'foot_stagger' => isKo ? '발 앞뒤 차이' : 'Feet front/back offset',
        'shoulder_over_pelvis' => isKo ? '어깨–골반 좌우 정렬' : 'Shoulders over pelvis',
        'torso_incline' => isKo ? '상체 기울기' : 'Torso tilt',
        'hand_width' => isKo ? '손 간격' : 'Hand width',
        'wrist_ahead' => isKo ? '손목 위치(어깨 기준)' : 'Wrists vs shoulders',
        'body_line' => isKo ? '몸통 일직선(엉덩이)' : 'Body line (hips)',
        'grip_width' => isKo ? '손목 간격(그립 근사)' : 'Wrist width (grip approx.)',
        'heel_width' => isKo ? '뒤꿈치 간격' : 'Heel width',
        'toe_out' => isKo ? '발끝 벌림' : 'Toe-out',
        'heel_toe' => isKo ? '뒤꿈치–발끝 높이' : 'Heel vs toe height',
        _ => item.key,
      };

  /// 숫자 문구. 관측이 부족하면 null (숫자를 보이지 않는다).
  static String? valueText(NativeSetupItem item, {required bool isKo}) {
    if (!item.measured) return null;
    final v = item.value!;
    String x(double d) => d.abs().toStringAsFixed(2);
    switch (item.key) {
      case 'feet_width':
      case 'heel_width':
        return isKo ? '골반 너비의 ${v.toStringAsFixed(1)}배' : '${v.toStringAsFixed(1)}× hip width';
      case 'toe_out':
        return isKo ? '발끝 간격 = 뒤꿈치 간격의 ${v.toStringAsFixed(2)}배' : 'toes ${v.toStringAsFixed(2)}× heel width';
      case 'heel_toe':
        final dir = v >= 0 ? (isKo ? '뒤꿈치가 아래' : 'heel lower') : (isKo ? '뒤꿈치가 위' : 'heel higher');
        return isKo ? '정강이의 ${x(v)}배 ($dir)' : '${x(v)}× shin ($dir)';
      case 'feet_width_shoulder':
      case 'hand_width':
      case 'grip_width':
        return isKo ? '어깨 너비의 ${v.toStringAsFixed(1)}배' : '${v.toStringAsFixed(1)}× shoulder width';
      case 'torso_incline':
        return isKo ? '수직에서 ${v.round()}°' : '${v.round()}° from vertical';
      case 'foot_symmetry':
      case 'shoulder_over_pelvis':
        final side = v >= 0 ? (isKo ? '왼쪽' : 'left') : (isKo ? '오른쪽' : 'right');
        return isKo ? '골반 너비의 ${x(v)}배 ($side)' : '${x(v)}× hip width ($side)';
      case 'foot_stagger':
        final ahead = v >= 0 ? (isKo ? '왼발이 앞' : 'left ahead') : (isKo ? '오른발이 앞' : 'right ahead');
        return isKo ? '다리 길이의 ${x(v)}배 ($ahead)' : '${x(v)}× leg length ($ahead)';
      case 'wrist_ahead':
        final dir = v >= 0 ? (isKo ? '머리 쪽' : 'towards the head') : (isKo ? '발 쪽' : 'towards the feet');
        return isKo ? '팔 길이의 ${x(v)}배 $dir' : '${x(v)}× arm length $dir';
      case 'body_line':
        final dir = v >= 0 ? (isKo ? '선보다 아래' : 'below the line') : (isKo ? '선보다 위' : 'above the line');
        return isKo ? '몸 길이의 ${x(v)}배 $dir' : '${x(v)}× body length $dir';
    }
    return v.toStringAsFixed(2);
  }

  static String? qualityText(NativeSetupItem item, {required bool isKo}) {
    if (!item.measured) return isKo ? '측정 중' : 'Measuring';
    if (item.quality == 'depth_estimated') return isKo ? '카메라 깊이 방향이라 추정치' : 'Along the camera depth — estimate';
    return null;
  }

  /// 저장한 내 기준과 비교한 조정 안내 (기준이 없으면 null). 관측 품질이 좋을 때만 네이티브가 cue 를 보낸다.
  static String? cueText(NativeSetupItem item, {required bool isKo}) {
    final cue = item.cue;
    if (item.ref == null || cue == null) return null;
    final wider = cue == 'increase';
    switch (item.key) {
      case 'feet_width':
      case 'feet_width_shoulder':
        return isKo
            ? (wider ? '양발 간격을 조금 넓혀 주세요' : '양발 간격을 조금 좁혀 주세요')
            : (wider ? 'Widen your stance a little' : 'Narrow your stance a little');
      case 'hand_width':
        return isKo
            ? (wider ? '손 간격을 조금 넓혀 주세요' : '손 간격을 조금 좁혀 주세요')
            : (wider ? 'Place your hands a little wider' : 'Place your hands a little closer');
      case 'grip_width':
        return isKo
            ? (wider ? '그립 간격을 조금 넓혀 주세요' : '그립 간격을 조금 좁혀 주세요')
            : (wider ? 'Widen your grip a little' : 'Narrow your grip a little');
      case 'torso_incline':
        return isKo
            ? (wider ? '저장한 기준보다 상체가 더 서 있어요' : '저장한 기준보다 상체가 더 숙여져 있어요')
            : (wider ? 'Torso more upright than your saved setup' : 'Torso more inclined than your saved setup');
    }
    final label = itemLabel(item, isKo: isKo);
    return isKo
        ? '$label: 저장한 내 기준보다 ${wider ? '작아요' : '커요'}'
        : '$label: ${wider ? 'below' : 'above'} your saved setup';
  }

  static String phaseText(NativeSetupStatus? s, {required bool isKo}) {
    if (s == null || s.phase == 'unavailable') return isKo ? '3D 자세를 기다리는 중이에요' : 'Waiting for the 3D pose';
    if (s.isReady) {
      return isKo
          ? '준비 자세가 확인됐습니다 — 관측이 안정적이라는 뜻이며, 올바른 자세라는 판정은 아니에요'
          : 'Setup confirmed — the pose is observed steadily; this is not a judgement that it is correct';
    }
    if (s.moving) return isKo ? '자세를 잠시 유지해 주세요' : 'Hold the pose for a moment';
    return isKo ? '현재 자세를 확인하고 있습니다' : 'Checking your current pose';
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    final profile = bodyProfile;
    const textStyle = TextStyle(color: AppColors.white, fontSize: 13);
    const dim = TextStyle(color: AppColors.darkTextSecondary, fontSize: 12);
    final cues = [
      for (final item in s?.items ?? const <NativeSetupItem>[])
        if (cueText(item, isKo: isKo) case final text?) text,
    ];
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isKo ? '$exerciseName 준비 자세' : '$exerciseName setup',
                    style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    key: const Key('setup_dismiss'),
                    icon: const Icon(Icons.close_rounded, color: AppColors.white, size: 20),
                    onPressed: onDismiss,
                  ),
              ],
            ),
            if (exerciseId == 'squat')
              Wrap(
                spacing: 6,
                children: [
                  for (final v in squatVariants)
                    ChoiceChip(
                      label: Text(variantLabel(v, isKo: isKo)),
                      selected: v == variant,
                      onSelected: onVariantChanged == null ? null : (_) => onVariantChanged!(v),
                    ),
                ],
              ),
            if (profile != null && (profile['hipWidthCm'] != null || profile['shoulderWidthCm'] != null))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    isKo ? '체형 측정(관절 중심):' : 'Body scan (joint centres):',
                    if (profile['hipWidthCm'] case final h?) isKo ? '골반 ${h.toStringAsFixed(0)} cm' : 'hips ${h.toStringAsFixed(0)} cm',
                    if (profile['shoulderWidthCm'] case final w?)
                      isKo ? '어깨 ${w.toStringAsFixed(0)} cm' : 'shoulders ${w.toStringAsFixed(0)} cm',
                  ].join(' '),
                  style: dim,
                ),
              ),
            const SizedBox(height: 6),
            Text(phaseText(s, isKo: isKo), key: const Key('setup_phase'), style: textStyle),
            if (s != null && !s.isReady && s.phase != 'unavailable')
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 6),
                child: LinearProgressIndicator(value: s.progress, color: AppColors.green, backgroundColor: AppColors.grey),
              ),
            const SizedBox(height: 6),
            for (final item in s?.items ?? const <NativeSetupItem>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${itemLabel(item, isKo: isKo)}: ', style: dim),
                    if (valueText(item, isKo: isKo) case final v?) TextSpan(text: v, style: textStyle),
                    if (qualityText(item, isKo: isKo) case final q?)
                      TextSpan(text: item.measured ? '  ($q)' : q, style: dim),
                  ]),
                ),
              ),
            // COCO17 (기본 모델)에는 발끝·뒤꿈치가 없어 발은 발목으로만 본다 — 정확한 발 간격·발 방향이 아님을 밝힌다.
            if (s != null && s.footSource != 'halpe26' && s.items.any((i) => i.key == 'feet_width'))
              Text(
                isKo ? '발 간격은 발목 기준이에요(발끝·뒤꿈치 위치와 발 방향은 이 모델로 볼 수 없어요).'
                    : 'Feet are measured at the ankles (toe/heel position and foot direction are not seen by this model).',
                key: const Key('setup_ankle_note'),
                style: dim,
              ),
            for (final cue in cues)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(cue, style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            if (!hasReference && s != null && s.isReady)
              Text(
                isKo ? '편한 준비 자세를 "내 기준"으로 저장하면 다음부터 비교해 드려요.' : 'Save a comfortable setup as yours to compare next time.',
                style: dim,
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('setup_reset'),
                  onPressed: onReset,
                  child: Text(isKo ? '다시 설정' : 'Reset'),
                ),
                FilledButton(
                  key: const Key('setup_save'),
                  onPressed: s != null && s.isReady && s.snapshot != null ? onSaveReference : null,
                  child: Text(isKo ? '이 자세를 내 기준으로 저장' : 'Save as my setup'),
                ),
              ],
            ),
            if (kDebugMode && s != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'debug ${s.phase} ${(s.progress * 100).round()}% moving=${s.moving} variant=${s.variant ?? '-'} '
                  '${s.items.map((i) => '${i.key}=${i.value?.toStringAsFixed(3) ?? '-'}/${i.quality}/d${i.depth}${i.ref != null ? '/ref${i.ref}' : ''}').join(' ')}',
                  style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 9),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
