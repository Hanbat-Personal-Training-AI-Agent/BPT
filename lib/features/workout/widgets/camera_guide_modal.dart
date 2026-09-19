import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

// ── 운동별 카메라 안내 데이터 ─────────────────────────────────────────────────
// 이미지 파일명을 변경할 때는 아래 Map의 imagePath만 수정하면 됩니다.
class CameraGuide {
  const CameraGuide({
    required this.imagePath,
    required this.angleKr,
    required this.angleEn,
  });
  final String imagePath;
  final String angleKr;
  final String angleEn;
}

const Map<String, CameraGuide> kCameraGuides = {
  'squat': CameraGuide(
    imagePath: 'assets/images/guide_squat.png',
    angleKr: '측면 45도',
    angleEn: '45° Side View',
  ),
  'pushup': CameraGuide(
    imagePath: 'assets/images/guide_pushup.png',
    angleKr: '측면 45도',
    angleEn: '45° Side View',
  ),
  'deadlift': CameraGuide(
    imagePath: 'assets/images/guide_deadlift.png',
    angleKr: '측면 45도',
    angleEn: '45° Side View',
  ),
  'benchpress': CameraGuide(
    imagePath: 'assets/images/guide_benchpress.png',
    angleKr: '아래쪽 시점',
    angleEn: 'Below View',
  ),
  'barbell-row': CameraGuide(
    imagePath: 'assets/images/guide_barbell_row.png',
    angleKr: '측면 45도',
    angleEn: '45° Side View',
  ),
};

// ── 진입점: 모달을 띄우고 확인 여부를 반환 ────────────────────────────────────
// true  → 사용자가 "확인했습니다" 누름 → 운동 시작
// false → 모달 닫기(뒤로가기/외부 탭) → 운동 시작 안 함
Future<bool> showCameraGuideModal({
  required BuildContext context,
  required String exerciseId,
  required String exerciseName,
  required bool isKo,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CameraGuideSheet(
      guide: kCameraGuides[exerciseId],
      exerciseName: exerciseName,
      isKo: isKo,
    ),
  );
  return result ?? false;
}

// ── 모달 시트 UI ──────────────────────────────────────────────────────────────
class _CameraGuideSheet extends StatelessWidget {
  const _CameraGuideSheet({
    required this.guide,
    required this.exerciseName,
    required this.isKo,
  });

  final CameraGuide? guide;
  final String exerciseName;
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들바
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // 제목
            Text(
              isKo ? '카메라 위치 안내' : 'Camera Placement',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),

            // 운동 이름 + 각도 배지
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  exerciseName,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (guide != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      isKo ? guide!.angleKr : guide!.angleEn,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // 안내 문구
            Text(
              isKo
                  ? '정확한 자세 인식을 위해 카메라를\n아래 예시처럼 위치해주세요.'
                  : 'Position the camera as shown below\nfor accurate pose detection.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),

            // 예시 이미지
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: guide != null
                  ? Image.asset(
                      guide!.imagePath,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          _ImagePlaceholder(isKo: isKo),
                    )
                  : _ImagePlaceholder(isKo: isKo),
            ),
            const SizedBox(height: 12),

            // 보조 문구
            Text(
              isKo
                  ? '카메라 위치를 확인한 뒤 운동을 시작해주세요.'
                  : 'Check the camera position before starting.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 24),

            // 확인 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  isKo ? '확인했습니다' : "Got it, let's go!",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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

// ── 이미지 미등록 시 플레이스홀더 ─────────────────────────────────────────────
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt_outlined,
              color: AppColors.primary, size: 44),
          const SizedBox(height: 10),
          Text(
            isKo ? '이미지 준비 중' : 'Image coming soon',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
