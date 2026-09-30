import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';

/// Shared field/button styles for the dark "찾기/가입" style auth screens
/// (account recovery, sign up) so both stay visually in sync.

/// Fixed page header (back arrow + centered title) for the dark auth
/// screens. Always pinned above the scrollable body — never put this
/// inside the same scroll view as the form content.
class AuthHeaderBar extends StatelessWidget {
  const AuthHeaderBar({super.key, required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: SizedBox(
          height: 60,
          child: Stack(alignment: Alignment.center, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: '뒤로 가기',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
              ),
            ),
          ]),
        ),
      );
}

/// Scaffold shared by the dark auth screens: a fixed [AuthHeaderBar] on
/// top, [body] as scrollable form content in the middle, and an optional
/// [bottomBar] (primary CTA, etc.) pinned below the scroll area so it's
/// always reachable without scrolling. [body] should NOT include its own
/// SingleChildScrollView/header/bottom buttons — this widget owns those.
class AuthScrollScaffold extends StatelessWidget {
  const AuthScrollScaffold({
    super.key,
    required this.title,
    required this.onBack,
    required this.body,
    this.bottomBar,
  });

  final String title;
  final VoidCallback onBack;
  final List<Widget> body;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Pretendard'),
          scaffoldBackgroundColor: AppColors.black,
        ),
        child: Scaffold(
          backgroundColor: AppColors.black,
          body: SafeArea(
            child: GestureDetector(
              // Tapping anywhere that isn't a field/button (empty space,
              // labels, a disabled button) should still blur the focused
              // field so its inline validation can show — relying only on
              // "tapped another field" misses most real dismiss gestures.
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: Column(
                children: [
                  AuthHeaderBar(title: title, onBack: onBack),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: body,
                      ),
                    ),
                  ),
                  if (bottomBar != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                      child: SizedBox(width: double.infinity, child: bottomBar),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      );
}

/// 아이디 입력용: 대문자는 소문자로 바꾸고, 영문 소문자·숫자만 20자까지 받는다.
final idInputFormatters = <TextInputFormatter>[
  TextInputFormatter.withFunction((oldValue, newValue) =>
      newValue.copyWith(text: newValue.text.toLowerCase())),
  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9]')),
  LengthLimitingTextInputFormatter(20),
];

/// 이메일 입력용: 영문·숫자·기호(공백 제외)만 허용해 한글 입력을 막는다.
final englishOnlyFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[\x21-\x7E]')),
];

OutlineInputBorder authFieldBorder(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color),
    );

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.focus,
    required this.hint,
    this.enabled = true,
    this.obscure = false,
    this.readOnly = false,
    this.onTap,
    this.keyboard,
    this.formatters,
    this.onChanged,
    this.suffix,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final bool enabled;
  final bool obscure;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: TextField(
          controller: controller,
          focusNode: focus,
          enabled: enabled,
          obscureText: obscure,
          readOnly: readOnly,
          onTap: onTap,
          keyboardType: keyboard,
          inputFormatters: formatters,
          onChanged: onChanged,
          autocorrect: false,
          enableSuggestions: false,
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(color: AppColors.white, fontSize: 16),
          cursorColor: AppColors.green,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF888888), fontSize: 14),
            filled: true,
            fillColor: AppColors.grey,
            suffixIcon: suffix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            border: authFieldBorder(const Color(0xFF2B2B2B)),
            enabledBorder: authFieldBorder(const Color(0xFF2B2B2B)),
            disabledBorder: authFieldBorder(const Color(0xFF2B2B2B)),
            focusedBorder: authFieldBorder(AppColors.green),
          ),
        ),
      );
}

Widget authEyeToggle(bool hidden, VoidCallback onTap) => IconButton(
      tooltip: hidden ? '비밀번호 표시' : '비밀번호 숨기기',
      onPressed: onTap,
      icon: Icon(Icons.visibility_outlined,
          size: 22, color: hidden ? const Color(0xFF888888) : AppColors.green),
    );

/// Purple pill used for a secondary action tucked beside a field
/// (이메일 인증하기 / 아이디 중복확인), which turns into a disabled
/// check-marked "완료" state once that action succeeds.
class AuthStatusButton extends StatelessWidget {
  const AuthStatusButton({
    super.key,
    required this.label,
    required this.complete,
    required this.onTap,
  });

  final String label;
  final bool complete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 90,
        height: 52,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: complete || onTap == null
                ? Colors.transparent
                : AppColors.purple,
            foregroundColor: AppColors.black,
            disabledForegroundColor:
                complete ? AppColors.purple : const Color(0xFF666666),
            side: BorderSide(
                color: complete
                    ? AppColors.purple
                    : onTap == null
                        ? const Color(0xFF333333)
                        : Colors.transparent),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (complete)
              const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_rounded, size: 17)),
            Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

/// Full-width bottom CTA pill, shared across the dark auth screens.
class AuthPillButton extends StatelessWidget {
  const AuthPillButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.disabledBackground,
    this.disabledForeground,
    this.borderColor,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final Color? disabledBackground;
  final Color? disabledForeground;
  final Color? borderColor;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: disabledBackground ?? background,
            disabledForegroundColor: disabledForeground ?? foreground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: borderColor != null
                  ? BorderSide(color: borderColor!)
                  : BorderSide.none,
            ),
          ),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      );
}
