import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _loginFormKey = GlobalKey<FormState>();

  // Login
  final _loginEmailCtrl = TextEditingController(); // username → email
  final _loginPasswordCtrl = TextEditingController();
  bool _obscureLogin = true;
  // 시안에서 자동 로그인 체크박스가 제거되어 기본값(false)으로 고정.
  // AuthNotifier.login(rememberMe:) 시그니처 호환을 위해 필드는 유지.
  final bool _autoLogin = false;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(s) async {
    final auth = ref.read(authNotifierProvider);
    if (kDebugMode) {
      // TEST ONLY: 백엔드 로그인 없이 네비게이션/화면 확인용 임시 우회. 배포 전 제거할 것.
      auth.debugSkipLogin();
      return;
    }
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;
    await auth.login(
      _loginEmailCtrl.text.trim(), // username → email
      _loginPasswordCtrl.text.trim(),
      rememberMe: _autoLogin,
    );
  }

  Future<void> _openAccountRecovery() async {
    final email = await context.push<String>(RouteConstants.accountRecovery);
    if (!mounted || email == null) return;
    _loginEmailCtrl.text = email;
    _loginPasswordCtrl.clear();
    setState(() => _obscureLogin = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final auth = ref.watch(authNotifierProvider);
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Pretendard'),
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          _buildBrand(),
                          const SizedBox(height: 2),
                          _buildHeroHeadline(s),
                          const SizedBox(height: 14),
                          _buildCharacterCard(s),
                          const SizedBox(height: 14),
                          _buildLoginForm(s, auth, theme),
                          const SizedBox(height: 28),
                          const Spacer(),
                          _buildStartButton(auth, s),
                          const SizedBox(height: 20),
                          _buildBottomSignUpToggle(s),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Brand mark (BPT) ─────────────────────────────────────────────────────
  Widget _buildBrand() {
    // w900이 Flutter 기본 최대 굵기라, 채운 글자 위에 stroke를 덧그려
    // 시각적으로 더 두껍게 보이도록 한다.
    return Stack(
      children: [
        const Text(
          'BPT',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            color: AppColors.green,
          ),
        ),
        Text(
          'BPT',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..strokeJoin = StrokeJoin.round
              ..color = AppColors.green,
          ),
        ),
      ],
    );
  }

  // ── Hero headline (시안: "자세는 내가 봐줄게, 넌 운동만 해") ────────────────
  Widget _buildHeroHeadline(s) {
    final isKo = s.locale == 'ko';
    if (isKo) {
      return RichText(
        text: const TextSpan(
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 32,
            fontWeight: FontWeight.w900,
            height: 1.08,
            color: AppColors.white,
          ),
          children: [
            TextSpan(text: '자세는\n내가 봐줄게,\n'),
            TextSpan(
              text: '넌 운동만 해',
              style: TextStyle(color: AppColors.green),
            ),
          ],
        ),
      );
    }
    return RichText(
      text: const TextSpan(
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 30,
          fontWeight: FontWeight.w900,
          height: 1.08,
          color: AppColors.white,
        ),
        children: [
          TextSpan(text: "I'll watch your form,\n"),
          TextSpan(
            text: 'you just work out',
            style: TextStyle(color: AppColors.green),
          ),
        ],
      ),
    );
  }

  // ── Character card (purple 배경 + 오리 캐릭터 + 말풍선 + 장식) ──────────────
  Widget _buildCharacterCard(s) {
    final isKo = s.locale == 'ko';
    return Center(
      child: AspectRatio(
        aspectRatio: 322 / 204,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: ColoredBox(
                color: AppColors.purple,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: h * 0.02,
                      width: w,
                      height: w,
                      child: Image.asset(
                        'assets/images/character/character_greeting.png',
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      ),
                    ),
                    Positioned(
                      left: w * 0.02,
                      top: 0,
                      child: Transform.rotate(
                        angle: -20 * math.pi / 180,
                        child: Image.asset(
                          'assets/images/decoration/spark_pink.png',
                          width: w * 0.22,
                          height: w * 0.22,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    Positioned(
                      right: w * 0.07,
                      top: h * 0.60,
                      child: Transform.rotate(
                        angle: -12 * math.pi / 180,
                        child: Image.asset(
                          'assets/images/decoration/heart_pink.png',
                          width: w * 0.21,
                          height: w * 0.21,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    Positioned(
                      left: w * 0.05,
                      bottom: h * 0.07,
                      child: Transform.rotate(
                        angle: -3 * math.pi / 180,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.black,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            isKo ? '안녕! 난 코리야!' : "Hi! I'm Kory!",
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              color: AppColors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Bottom sign-up link (시안: "처음이야? 회원가입 하기") ──────────────────
  Widget _buildBottomSignUpToggle(s) {
    final isKo = s.locale == 'ko';
    return Center(
      child: GestureDetector(
        onTap: () => context.push(RouteConstants.signUp),
        behavior: HitTestBehavior.opaque,
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontFamily: 'Pretendard', fontSize: 14),
            children: [
              TextSpan(
                text: isKo ? '처음이야? ' : 'First time? ',
                style: const TextStyle(
                  color: Color(0xFF8A8F94),
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextSpan(
                text: isKo ? '회원가입 하기' : 'Sign up',
                style: const TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Login Form (시안 재구성) ────────────────────────────────────────────────
  Widget _buildLoginForm(s, AuthNotifier auth, ThemeData theme) {
    final isKo = s.locale == 'ko';
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLoginField(
            controller: _loginEmailCtrl,
            hint: isKo ? '아이디' : 'Email',
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return s.idRequired;
              if (!v.contains('@')) return s.invalidEmail;
              return null;
            },
          ),
          const SizedBox(height: 10),
          _buildLoginField(
            controller: _loginPasswordCtrl,
            hint: '• • • • • • • •',
            obscureText: _obscureLogin,
            suffixIcon: IconButton(
              icon: Icon(
                Icons.visibility_outlined,
                size: 22,
                // 비공개일 때는 회색, 표시할 때는 라임색으로 변한다.
                color:
                    _obscureLogin ? const Color(0xFF8A8F94) : AppColors.green,
              ),
              onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
            ),
            validator: (v) => v == null || v.length < 8 ? s.minEightChars : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _openAccountRecovery,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                foregroundColor: const Color(0xFF8A8F94),
              ),
              child: Text(
                isKo ? '아이디/비밀번호 찾기' : 'Find ID / Password',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (auth.error != null) ...[
            _buildErrorBox(auth.error!, s),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  // 시안 스타일 입력 필드: grey 배경, 큰 라운드, placeholder, 무테 포커스
  Widget _buildLoginField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      cursorColor: const Color(0xFF8A8F94),
      cursorWidth: 1.5,
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF7A7F84),
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: AppColors.grey,
        suffixIcon: suffixIcon,
        suffixIconColor: const Color(0xFF8A8F94),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        // 시안: 입력창은 테두리 없이 배경색만으로 구분. 포커스 시에도 무테.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF2C2C2C)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF2C2C2C)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF2C2C2C)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.red, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.red, width: 1.2),
        ),
      ),
    );
  }

  // 시안 CTA: green 배경 + black 텍스트
  Widget _buildStartButton(AuthNotifier auth, s) {
    final isKo = s.locale == 'ko';
    final label = isKo ? '시작하기' : 'Get Started';
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: auth.isLoading ? null : () => _submit(s),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: AppColors.black,
          disabledBackgroundColor: AppColors.green.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: auth.isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.black),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }

  String _localizeError(String code, s) {
    final isKo = s.locale == 'ko';
    switch (code) {
      case 'username_or_password_incorrect':
        return isKo
            ? '이메일 또는 비밀번호가 올바르지 않아요.'
            : 'Email or password is incorrect.';
      case 'username_already_exists':
        return isKo ? '이미 사용 중인 이메일이에요.' : 'This email is already in use.';
      case 'password_too_weak':
        return isKo ? '비밀번호가 너무 짧아요. 8자 이상 입력해주세요.' : 'Password is too weak.';
      case 'invalid_email':
        return isKo ? '올바른 이메일 형식이 아니에요.' : 'Invalid email format.';
      default:
        return isKo
            ? '오류가 발생했어요. 다시 시도해주세요.'
            : 'Something went wrong. Please try again.';
    }
  }

  Widget _buildErrorBox(String error, s) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _localizeError(error, s),
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
