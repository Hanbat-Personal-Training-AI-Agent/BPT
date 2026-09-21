import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

// ── 운동별 카메라 각도 가이드 데이터 ───────────────────────────────────────
// 모든 운동이 120° 사선 구도를 쓰기 때문에 각도 값은 고정이고, 운동마다
// 다른 건 캐릭터 그림과 "{운동}는/은" 조사가 붙은 헤드라인 앞부분뿐이다.
class _CameraGuideInfo {
  const _CameraGuideInfo({
    required this.imagePath,
    required this.topicKo,
    required this.nameEn,
  });
  final String imagePath;
  final String topicKo;
  final String nameEn;
}

const Map<String, _CameraGuideInfo> _kCameraGuides = {
  'squat': _CameraGuideInfo(
    imagePath: 'assets/images/character/camera_squat.png',
    topicKo: '스쿼트는',
    nameEn: 'Squat',
  ),
  'benchpress': _CameraGuideInfo(
    imagePath: 'assets/images/character/camera_benchpress.png',
    topicKo: '벤치프레스는',
    nameEn: 'Bench press',
  ),
  'deadlift': _CameraGuideInfo(
    imagePath: 'assets/images/character/camera_deadlift.png',
    topicKo: '데드리프트는',
    nameEn: 'Deadlift',
  ),
  'barbell-row': _CameraGuideInfo(
    imagePath: 'assets/images/character/camera_barbellrow.png',
    topicKo: '바벨로우는',
    nameEn: 'Barbell row',
  ),
  'pushup': _CameraGuideInfo(
    imagePath: 'assets/images/character/camera_pushup.png',
    topicKo: '푸쉬업은',
    nameEn: 'Push-up',
  ),
  'lat-pulldown': _CameraGuideInfo(
    imagePath: 'assets/images/character/camera_latpulldown.png',
    topicKo: '랫풀다운은',
    nameEn: 'Lat pulldown',
  ),
};

class CameraGuideScreen extends ConsumerWidget {
  const CameraGuideScreen({
    super.key,
    required this.exerciseId,
    required this.targetReps,
    required this.targetSets,
  });

  final String exerciseId;
  final int targetReps;
  final int targetSets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final isKo = s.locale == 'ko';
    final guide = _kCameraGuides[exerciseId] ?? _kCameraGuides['squat']!;

    void start() {
      context.push(
        RouteConstants.nativePoseWorkout,
        extra: {
          'exerciseId': exerciseId,
          'targetReps': targetReps,
          'targetSets': targetSets,
        },
      );
    }

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: Column(
            children: [
              _GuideHeader(isKo: isKo),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Headline(isKo: isKo, guide: guide),
                      const SizedBox(height: 16),
                      _IllustrationCard(imagePath: guide.imagePath),
                      const SizedBox(height: 16),
                      _ChecklistCard(isKo: isKo),
                      const SizedBox(height: 16),
                      _KoriBanner(isKo: isKo),
                      const SizedBox(height: 28),
                      _StartCtaButton(isKo: isKo, onTap: start),
                    ],
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

// ── 헤더: 뒤로가기 / 타이틀 / 도움말 ────────────────────────────────────────
class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          Expanded(
            child: Text(
              isKo ? '폰 어디 둘까?' : 'Where should I put my phone?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showHelpSheet(context, isKo),
            behavior: HitTestBehavior.opaque,
            child: Text(
              isKo ? '도움말' : 'Help',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 도움말 바텀시트: 코리가 말투로 알려주는 트러블슈팅 팁 ───────────────────
Future<void> _showHelpSheet(BuildContext context, bool isKo) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.grey,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _HelpSheet(isKo: isKo),
  );
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet({required this.isKo});
  final bool isKo;

  static const _tipsKo = [
    '거치대가 없어도 괜찮아! 책이나 의자에 기대서 세워도 충분해',
    '머리부터 발끝까지 화면에 다 들어와야 내가 자세를 정확히 봐줄 수 있어',
    '조명이 너무 어두우면 나도 잘 안 보여... 밝은 곳에서 찍어줘!',
  ];
  static const _tipsEn = [
    "No stand? No problem — leaning it on a book or a chair works too",
    'Fit your whole body in frame, head to toe, so I can check your form',
    "Too dark and I can't see you well... find some brighter light!",
  ];

  @override
  Widget build(BuildContext context) {
    final tips = isKo ? _tipsKo : _tipsEn;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Image.asset(
                'assets/images/character/face.png',
                width: 40,
                height: 40,
              ),
              const SizedBox(width: 10),
              Text(
                isKo ? '코리의 도움말' : "Kori's help",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final tip in tips) ...[
            _HelpTipRow(text: tip),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: double.infinity,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                isKo ? '알겠어!' : 'Got it!',
                style: const TextStyle(
                  color: AppColors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpTipRow extends StatelessWidget {
  const _HelpTipRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 8, right: 10),
          decoration: const BoxDecoration(
            color: AppColors.green,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── 헤드라인: "{운동}는 / 120° 사선이 제일 잘 보여" ─────────────────────────
class _Headline extends StatelessWidget {
  const _Headline({required this.isKo, required this.guide});
  final bool isKo;
  final _CameraGuideInfo guide;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      height: 1.35,
    );
    if (!isKo) {
      return RichText(
        text: TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: '${guide.nameEn}\n'),
            const TextSpan(
              text: '120° angle ',
              style: TextStyle(color: AppColors.green),
            ),
            const TextSpan(text: 'works best'),
          ],
        ),
      );
    }
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: '${guide.topicKo}\n'),
          const TextSpan(
            text: '120° 사선',
            style: TextStyle(color: AppColors.green),
          ),
          const TextSpan(text: '이 제일 잘 보여'),
        ],
      ),
    );
  }
}

// ── 보라색 카드 안에 운동별 카메라 각도 캐릭터 그림 ─────────────────────────
class _IllustrationCard extends StatelessWidget {
  const _IllustrationCard({required this.imagePath});
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.purple,
        borderRadius: BorderRadius.circular(24),
      ),
      child: AspectRatio(
        aspectRatio: 1.15,
        child: Image.asset(imagePath, fit: BoxFit.contain),
      ),
    );
  }
}

// ── 체크리스트 카드 ─────────────────────────────────────────────────────────
class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _ChecklistRow(
            warning: false,
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                children: isKo
                    ? const [
                        TextSpan(text: '그림처럼 '),
                        TextSpan(
                          text: '비스듬한 사선 방향에',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(text: ' 폰을 세워 둬'),
                      ]
                    : const [
                        TextSpan(text: 'Stand your phone at '),
                        TextSpan(
                          text: 'an angled diagonal',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(text: ' like in the picture'),
                      ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ChecklistRow(
            warning: false,
            child: Text(
              isKo
                  ? '몸이 카메라에 들어오게 맞춰줘'
                  : 'Make sure your whole body is in frame',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ChecklistRow(
            warning: true,
            child: Text(
              isKo
                  ? '폰은 세로로, 거치대에 고정해줘'
                  : 'Keep it vertical and mounted on a stand',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.warning, required this.child});
  final bool warning;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: warning ? AppColors.pink : AppColors.green,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            warning ? Icons.priority_high_rounded : Icons.check_rounded,
            size: 13,
            color: AppColors.black,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}

// ── 코리 배너: "나처럼 카메라 세워줘! 자세는 내가 볼게" ─────────────────────
class _KoriBanner extends StatelessWidget {
  const _KoriBanner({required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.pink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/character/face.png',
            width: 44,
            height: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isKo
                  ? '나처럼 카메라 세워줘! 자세는 내가 볼게'
                  : "Set your camera up like me! I'll watch your form",
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 하단 버튼: 끝! 시작할게 ─────────────────────────────────────────────────
class _StartCtaButton extends StatelessWidget {
  const _StartCtaButton({required this.isKo, required this.onTap});
  final bool isKo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          isKo ? '끝! 시작할게' : "Done! Let's start",
          style: const TextStyle(
            color: AppColors.black,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
