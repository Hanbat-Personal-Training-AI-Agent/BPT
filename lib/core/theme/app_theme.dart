import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// 앱은 모든 화면에서 다크 테마를 명시적으로 씌우고 있어(각 화면의
/// `Theme(data: AppTheme.darkTheme, ...)` 래핑) 라이트 테마는 실제로 노출된
/// 적이 없다. 그래서 라이트/다크 분기 없이 다크 전용 테마 하나만 만든다 —
/// `AppTheme.darkTheme`라는 이름은 그대로 유지해 기존 호출부를 안 건드린다.
class AppTheme {
  static ThemeData get darkTheme => _build();

  static ThemeData _build() {
    const bg = AppColors.darkBackground;
    const surface = AppColors.darkSurface;
    const card = AppColors.darkCard;
    const textPrimary = AppColors.darkTextPrimary;
    const textSecondary = AppColors.darkTextSecondary;
    const divider = AppColors.darkDivider;
    const inputFill = AppColors.darkInputFill;

    final base = ThemeData.dark();

    // Boosted text theme for readability
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.inter(
          fontSize: 57, fontWeight: FontWeight.w800, color: textPrimary),
      displayMedium: GoogleFonts.inter(
          fontSize: 45, fontWeight: FontWeight.w700, color: textPrimary),
      displaySmall: GoogleFonts.inter(
          fontSize: 36, fontWeight: FontWeight.w700, color: textPrimary),
      headlineLarge: GoogleFonts.inter(
          fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary),
      headlineMedium: GoogleFonts.inter(
          fontSize: 28, fontWeight: FontWeight.w700, color: textPrimary),
      headlineSmall: GoogleFonts.inter(
          fontSize: 26, fontWeight: FontWeight.w700, color: textPrimary),
      titleLarge: GoogleFonts.inter(
          fontSize: 22, fontWeight: FontWeight.w800, color: textPrimary),
      titleMedium: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
      titleSmall: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
      bodyLarge: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.w500, color: textPrimary),
      bodyMedium: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w500, color: textPrimary),
      bodySmall: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w500, color: textSecondary),
      labelLarge: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
      labelMedium: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
      labelSmall: GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w500, color: textSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.green,
        onPrimary: AppColors.black,
        secondary: AppColors.purple,
        onSecondary: Colors.white,
        error: AppColors.red,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: card,
      ),
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(size: 26),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: AppColors.black,
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.green,
          side: const BorderSide(color: AppColors.green, width: 1.5),
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.green, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.red, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: GoogleFonts.inter(
          fontSize: 15,
          color: textSecondary,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: GoogleFonts.inter(fontSize: 15, color: textSecondary),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: AppColors.green,
        unselectedItemColor: textSecondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle:
            GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: inputFill,
        labelStyle: GoogleFonts.inter(fontSize: 14, color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.green,
        unselectedLabelColor: textSecondary,
        indicatorColor: AppColors.green,
        labelStyle:
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      iconTheme: const IconThemeData(size: 26),
    );
  }
}
