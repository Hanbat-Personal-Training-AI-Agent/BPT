import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/body_mesh_reveal.dart';

/// "짜잔" screen between the analysis and the result: the user's own 3D body, revealed like a
/// new card, to look at and turn by hand. Without a mesh it goes straight on to the unchanged
/// result screen. Only reached when [kBodyMeshReveal] is on.
class OnboardingMeshScreen extends StatefulWidget {
  const OnboardingMeshScreen({super.key, required this.jobId});

  final String jobId;

  @override
  State<OnboardingMeshScreen> createState() => _OnboardingMeshScreenState();
}

class _OnboardingMeshScreenState extends State<OnboardingMeshScreen> {
  bool _revealed = false;

  void _next() => context.go(RouteConstants.onboardingResult);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              AnimatedOpacity(
                opacity: _revealed ? 1 : 0,
                duration: const Duration(milliseconds: 600),
                child: const Text('짜잔! 이게 너의 3D 몸이야',
                    style: TextStyle(
                        color: AppColors.white,
                        fontFamily: 'Pretendard',
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  // The card the mesh is presented on; the SceneKit view is transparent.
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: AppColors.green.withValues(alpha: 0.5),
                        width: 1.5),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF2A2140), AppColors.grey],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BodyMeshReveal(
                      jobId: widget.jobId,
                      onUnavailable: _next,
                      onRevealed: () => Future.delayed(
                          const Duration(milliseconds: 1600), () {
                        if (mounted) setState(() => _revealed = true);
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedOpacity(
                opacity: _revealed ? 1 : 0,
                duration: const Duration(milliseconds: 600),
                child: const Text('드래그해서 돌려봐',
                    style: TextStyle(
                        color: Color(0xFF9AA0A6),
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: AppColors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('다음',
                      style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
