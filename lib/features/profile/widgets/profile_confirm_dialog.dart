import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// 로그아웃/회원 탈퇴처럼 되돌리기 어려운 액션을 확인받는 다이얼로그.
///
/// `showDialog`가 여는 다이얼로그 라우트는 각 화면을 감싸는 로컬
/// `Theme(data: AppTheme.darkTheme, ...)` 밖(앱 루트 테마) 컨텍스트에 붙기
/// 때문에, 그냥 AlertDialog를 쓰면 Material3 surfaceTint 등으로 배경색이
/// 지정해도 탁하게 뜨거나 버튼 리플 색이 앱 톤과 안 맞게 보일 수 있다.
/// 여기서 다크 테마와 틴트를 명시적으로 고정해 로그아웃/탈퇴 두 다이얼로그가
/// 항상 같은 톤으로 보이게 한다.
Future<void> showProfileConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required VoidCallback onConfirm,
  Color confirmColor = AppColors.red,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => Theme(
      data: AppTheme.darkTheme,
      child: AlertDialog(
        backgroundColor: AppColors.grey,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.6),
            ),
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: confirmColor),
            onPressed: () {
              Navigator.pop(dialogCtx);
              onConfirm();
            },
            child: Text(
              confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}
