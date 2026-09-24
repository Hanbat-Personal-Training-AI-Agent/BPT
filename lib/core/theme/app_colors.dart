import 'package:flutter/material.dart';

class AppColors {
  // ── BPT Brand Palette ─────────────────────────────────────
  // 앱 전체가 쓰는 유일한 팔레트. 다크 전용 디자인이라 별도의 라이트/구
  // 브랜드(청록·주황) 팔레트는 두지 않는다.
  static const Color green = Color(0xFFBFED5F); // 포인트 액션 / CTA
  static const Color purple = Color(0xFFAC88F6); // 캐릭터 카드 / 강조 배경
  static const Color red = Color(0xFFD56140); // 경고 / 강한 강조
  static const Color pink = Color(0xFFFE9894); // 장식 / 서브 포인트
  static const Color black = Color(0xFF101010); // 기본 배경
  static const Color white = Color(0xFFEDF1F4); // 기본 전경/텍스트
  static const Color grey = Color(0xFF1E1E1E); // 카드 / 입력 필드 배경

  // ── Dark Mode (AppTheme가 ThemeData를 만들 때 쓰는 토큰) ──────
  static const Color darkBackground = Color(0xFF0F1117);
  static const Color darkSurface = Color(0xFF1A1D27);
  static const Color darkCard = Color(0xFF242838);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkDivider = Color(0xFF2D3148);
  static const Color darkInputFill = Color(0xFF2A2D3E);
}
