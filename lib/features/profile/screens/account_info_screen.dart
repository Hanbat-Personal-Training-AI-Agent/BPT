import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_confirm_dialog.dart';

/// 프로필 > "계정 · 개인정보" 진입 화면.
/// 이용약관/개인정보 처리방침 열람, 마케팅 수신 동의, 회원 탈퇴를 다룬다.
/// 로그인 정보(아이디·이메일 확인, 비밀번호 변경)는 이미 "내 정보 수정"
/// 화면이 담당하므로 여기서 중복하지 않는다.
class AccountInfoScreen extends ConsumerWidget {
  const AccountInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: Column(
            children: [
              _AccountInfoHeader(
                title: '계정 · 개인정보',
                onBack: () => context.pop(),
              ),
              const Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel('약관 및 정책'),
                      SizedBox(height: 8),
                      _PolicyCard(),
                      SizedBox(height: 20),
                      _SectionLabel('마케팅 정보'),
                      SizedBox(height: 8),
                      _MarketingConsentCard(),
                    ],
                  ),
                ),
              ),
              // 스크롤 영역 밖, 화면 맨 아래에 고정.
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: _DeleteAccountLink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 헤더 (뒤로가기 + 타이틀, 정책 문서 화면과 공유) ─────────────────────────
class _AccountInfoHeader extends StatelessWidget {
  const _AccountInfoHeader({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 48), // 뒤로가기 버튼과 균형 맞추기용 더미 폭
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      );
}

// ── 이용약관 / 개인정보 처리방침 ────────────────────────────────────────
class _PolicyCard extends StatelessWidget {
  const _PolicyCard();

  @override
  Widget build(BuildContext context) {
    final divider = Divider(
        height: 1,
        indent: 18,
        endIndent: 18,
        color: Colors.white.withValues(alpha: 0.08));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _InfoRow(
            label: '이용약관',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const _PolicyDocumentScreen(
                title: '이용약관',
                body: _termsOfServiceText,
              ),
            )),
          ),
          divider,
          _InfoRow(
            label: '개인정보 처리방침',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const _PolicyDocumentScreen(
                title: '개인정보 처리방침',
                body: _privacyPolicyText,
              ),
            )),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.35), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── 약관/정책 전문 뷰어 ────────────────────────────────────────────────────
class _PolicyDocumentScreen extends StatelessWidget {
  const _PolicyDocumentScreen({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: Column(
            children: [
              _AccountInfoHeader(
                title: title,
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Text(
                    body,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 14,
                      height: 1.7,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _termsOfServiceText = '''
제1조 (목적)
이 약관은 BPT(이하 "회사")가 제공하는 AI 운동 코칭 서비스(이하 "서비스")의 이용과 관련하여 회사와 회원 간의 권리, 의무 및 책임사항을 정함을 목적으로 합니다.

제2조 (정의)
1. "서비스"란 회사가 제공하는 운동 자세 분석, 반복 횟수 측정, 운동 기록 관리 등의 기능을 말합니다.
2. "회원"이란 이 약관에 동의하고 회사와 이용계약을 체결한 자를 말합니다.

제3조 (약관의 효력 및 변경)
1. 이 약관은 서비스 화면에 게시함으로써 효력이 발생합니다.
2. 회사는 관련 법령을 위반하지 않는 범위에서 약관을 개정할 수 있으며, 개정 시 서비스 내 공지합니다.

제4조 (서비스의 제공 및 변경)
1. 회사는 운동 자세 인식, 반복 횟수 측정, 기록 저장 등의 기능을 제공합니다.
2. 서비스의 내용은 회사의 사정에 따라 추가, 변경되거나 중단될 수 있습니다.

제5조 (회원의 의무)
1. 회원은 서비스 이용 시 관련 법령과 이 약관을 준수해야 합니다.
2. 회원은 타인의 계정을 도용하거나 허위 정보를 등록해서는 안 됩니다.

제6조 (서비스 이용의 제한)
회사는 회원이 이 약관을 위반한 경우 사전 통지 후 서비스 이용을 제한하거나 이용계약을 해지할 수 있습니다.

제7조 (면책조항)
1. 회사는 천재지변, 통신장애 등 불가항력적인 사유로 서비스를 제공할 수 없는 경우 책임을 지지 않습니다.
2. 서비스가 제공하는 자세 피드백은 참고용이며, 운동 중 발생하는 부상 등에 대해서는 이용자 본인의 주의 의무가 우선합니다.

부칙
이 약관은 2026년 1월 1일부터 적용됩니다.''';

const _privacyPolicyText = '''
BPT(이하 "회사")는 이용자의 개인정보를 중요하게 생각하며, 「개인정보 보호법」 등 관련 법령을 준수합니다.

1. 수집하는 개인정보 항목
· 필수: 이름, 아이디, 이메일, 비밀번호, 생년월일
· 선택: 전화번호, 성별, 키, 몸무게, 운동 목표
· 서비스 이용 중 자동 수집: 운동 기록, 체형 측정 결과, 기기 정보

2. 개인정보의 수집 및 이용 목적
· 회원 가입 및 본인 확인
· 운동 자세 분석 및 맞춤 피드백 제공
· 운동 기록 저장 및 리포트 제공
· 고객 문의 응대

3. 개인정보의 보유 및 이용 기간
회원 탈퇴 시 지체 없이 파기합니다. 단, 관계 법령에 따라 보존이 필요한 경우 해당 기간 동안 보관합니다.

4. 개인정보의 제3자 제공
회사는 이용자의 동의 없이 개인정보를 외부에 제공하지 않습니다. 다만 법령에 근거하거나 수사기관의 적법한 요청이 있는 경우는 예외로 합니다.

5. 이용자의 권리
이용자는 언제든지 본인의 개인정보를 조회·수정할 수 있으며, 회원 탈퇴를 통해 개인정보 삭제를 요청할 수 있습니다.

6. 개인정보 보호책임자
· 담당: BPT 개인정보보호책임자
· 문의: support@bpt.app

부칙
이 방침은 2026년 1월 1일부터 시행됩니다.''';

// ── 마케팅 정보 수신 동의 ────────────────────────────────────────────────
class _MarketingConsentCard extends ConsumerWidget {
  const _MarketingConsentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(marketingConsentEnabledProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '마케팅 정보 수신 동의',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3),
                Text(
                  '혜택·이벤트 소식을 받아볼게요 (선택)',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          // 알림 토글과 동일한 스타일.
          Transform.scale(
            scale: 0.95,
            child: Switch(
              value: enabled,
              onChanged: (v) =>
                  ref.read(marketingConsentEnabledProvider.notifier).state = v,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeTrackColor: AppColors.green,
              thumbColor: const WidgetStatePropertyAll(AppColors.black),
              trackOutlineColor:
                  const WidgetStatePropertyAll(Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 회원 탈퇴 ──────────────────────────────────────────────────────────────
class _DeleteAccountLink extends ConsumerWidget {
  const _DeleteAccountLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: GestureDetector(
        onTap: () => _confirmDeleteAccount(context, ref),
        child: Text(
          '회원 탈퇴',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
  showProfileConfirmDialog(
    context,
    title: '회원 탈퇴',
    message: '탈퇴하면 운동 기록, 체형 정보 등 모든 데이터가 삭제되고 복구할 수 없어. 정말 탈퇴할까?',
    confirmLabel: '탈퇴하기',
    onConfirm: () => ref.read(authNotifierProvider).deleteAccount(),
  );
}
