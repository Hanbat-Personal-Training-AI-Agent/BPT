import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/workout_orientation.dart';

// ── 운동별 카메라 각도 가이드 데이터 ───────────────────────────────────────
// 모든 운동이 120° 사선 구도를 쓰기 때문에 각도 값은 고정이고, 운동마다
// 다른 건 캐릭터 그림과 "{운동}는/은" 조사가 붙은 헤드라인 앞부분뿐이다.
// 푸쉬업은 몸이 옆으로 길어서 폰을 가로로 두고, 이 화면부터 가로로 보여준다
// ([isLandscapeWorkout]).
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

class CameraGuideScreen extends ConsumerStatefulWidget {
  const CameraGuideScreen({
    super.key,
    required this.exerciseId,
    required this.targetReps,
    required this.targetSets,
    this.setWeightsKg = const [],
    this.setReps = const [],
    this.restSeconds = 60,
  });

  final String exerciseId;
  final int targetReps;
  final int targetSets;
  final List<int> setWeightsKg;
  final List<int> setReps;
  final int restSeconds;

  @override
  ConsumerState<CameraGuideScreen> createState() => _CameraGuideScreenState();
}

class _CameraGuideScreenState extends ConsumerState<CameraGuideScreen> {
  _CameraGuideInfo get _guide =>
      _kCameraGuides[widget.exerciseId] ?? _kCameraGuides['squat']!;

  bool get _landscape => isLandscapeWorkout(widget.exerciseId);

  // 가로 운동은 여기서 가로로 돌리고, 이 화면이 닫힐 때 세로로 되돌린다.
  // 위에 쌓이는 운동 화면은 가로를 그대로 쓰고, 결과 화면으로 갈 때 세로로 돌린다.
  @override
  void initState() {
    super.initState();
    if (_landscape) lockLandscape();
  }

  @override
  void dispose() {
    if (_landscape) lockPortrait();
    super.dispose();
  }

  void _start() {
    context.push(
      RouteConstants.nativePoseWorkout,
      extra: {
        'exerciseId': widget.exerciseId,
        'targetReps': widget.targetReps,
        'targetSets': widget.targetSets,
        'setWeightsKg': widget.setWeightsKg,
        'setReps': widget.setReps,
        'restSeconds': widget.restSeconds,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final isKo = s.locale == 'ko';
    final guide = _guide;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: Column(
            children: [
              _GuideHeader(isKo: isKo),
              Expanded(
                child: isLandscape
                    ? _landscapeBody(isKo, guide)
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Headline(isKo: isKo, guide: guide),
                            const SizedBox(height: 16),
                            _IllustrationCard(imagePath: guide.imagePath),
                            const SizedBox(height: 16),
                            _ChecklistCard(isKo: isKo, landscape: _landscape),
                            const SizedBox(height: 16),
                            _KoriBanner(isKo: isKo),
                            const SizedBox(height: 28),
                            _StartCtaButton(isKo: isKo, onTap: _start),
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

  /// 가로 화면: 왼쪽에 그림, 오른쪽에 설명과 시작 버튼.
  Widget _landscapeBody(bool isKo, _CameraGuideInfo guide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.purple,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Image.asset(guide.imagePath, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Headline(isKo: isKo, guide: guide),
                  const SizedBox(height: 12),
                  _ChecklistCard(isKo: isKo, landscape: _landscape),
                  const SizedBox(height: 12),
                  _KoriBanner(isKo: isKo),
                  const SizedBox(height: 16),
                  _StartCtaButton(isKo: isKo, onTap: _start),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 헤더: 뒤로가기 / 타이틀 ────────────────────────────────────────
class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
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
          // 뒤로가기 버튼과 같은 너비로 비워 타이틀을 가운데에 둔다.
          const SizedBox(width: 48),
        ],
      ),
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
  const _ChecklistCard({required this.isKo, required this.landscape});
  final bool isKo;

  /// 폰을 가로로 두는 운동인지.
  final bool landscape;

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
              switch ((isKo, landscape)) {
                (true, false) => '폰은 세로로, 거치대에 고정해줘',
                (true, true) => '폰은 가로로, 거치대에 고정해줘',
                (false, false) => 'Keep it vertical and mounted on a stand',
                (false, true) => 'Keep it horizontal and mounted on a stand',
              },
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
