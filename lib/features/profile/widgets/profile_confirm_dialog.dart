import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 로그아웃/회원 탈퇴처럼 되돌리기 어려운 액션을 확인받는 다이얼로그.
///
/// 운동 화면의 "끝내기" 확인 모달과 같은 디자인이다: 짙은 회색 카드 + 회색
/// 테두리, 왼쪽에 코리, 오른쪽에 제목·안내, 아래에 버튼 두 개
/// (왼쪽 확인 액션 = 회색, 오른쪽 취소 = 초록).
///
/// 다이얼로그 라우트는 화면별 로컬 Theme 밖에 붙으므로, 색은 테마에 기대지
/// 않고 여기서 직접 지정한다.
Future<void> showProfileConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required VoidCallback onConfirm,
  String cancelLabel = '취소',
  String character = 'assets/images/character/cry.png',
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (dialogCtx) => Dialog(
      backgroundColor: AppColors.grey,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0xFF5C5C5C)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Image.asset(character, width: 76, height: 76),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: TextStyle(
                          color: AppColors.white.withValues(alpha: 0.65),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: confirmLabel,
                    primary: false,
                    onTap: () {
                      Navigator.pop(dialogCtx);
                      onConfirm();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DialogButton(
                    label: cancelLabel,
                    primary: true,
                    onTap: () => Navigator.pop(dialogCtx),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              primary ? AppColors.green : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: primary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? AppColors.black : Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
