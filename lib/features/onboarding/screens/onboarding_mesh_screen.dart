import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../models/body_analysis_result.dart';
import '../widgets/body_mesh_reveal.dart';

/// The complete analysis result, including a small, already prepared mesh.
class OnboardingMeshScreen extends StatelessWidget {
  const OnboardingMeshScreen(
      {super.key, this.analysis = const BodyAnalysisResult()});

  final BodyAnalysisResult analysis;

  @override
  Widget build(BuildContext context) {
    final rows = analysis.summary.entries.toList();
    return Theme(
      data: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Pretendard'),
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 16),
                const Text('신체분석 완료!',
                    style: TextStyle(
                        color: AppColors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.37,
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: AppColors.green.withValues(alpha: 0.5)),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF2A2140), AppColors.grey],
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BodyMeshReveal(meshId: analysis.meshId),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: rows.isEmpty
                      ? const Center(
                          child: Text('표시할 신체 정보가 없어요.',
                              style: TextStyle(color: Color(0xFF9AA0A6))))
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                                color: AppColors.grey,
                                borderRadius: BorderRadius.circular(14)),
                            child: Row(children: [
                              Expanded(
                                  child: Text(rows[index].key,
                                      style: const TextStyle(
                                          color: Color(0xFF9AA0A6),
                                          fontSize: 14))),
                              Text(rows[index].value,
                                  style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go(RouteConstants.home),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: AppColors.black,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('넘어가기',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
