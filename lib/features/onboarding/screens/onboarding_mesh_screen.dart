import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/body_analysis_result.dart';
import '../widgets/body_mesh_reveal.dart';

/// The complete analysis result, including a small, already prepared mesh.
class OnboardingMeshScreen extends ConsumerStatefulWidget {
  const OnboardingMeshScreen(
      {super.key, this.analysis = const BodyAnalysisResult()});

  final BodyAnalysisResult analysis;

  @override
  ConsumerState<OnboardingMeshScreen> createState() =>
      _OnboardingMeshScreenState();
}

class _OnboardingMeshScreenState extends ConsumerState<OnboardingMeshScreen> {
  bool _presentedMesh = false;
  bool _releasedUnused = false;

  void _releaseUnused() {
    if (_presentedMesh || _releasedUnused) return;
    _releasedUnused = true;
    unawaited(BodyMeshReveal.release(widget.analysis.meshId));
  }

  @override
  void didUpdateWidget(covariant OnboardingMeshScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.analysis, widget.analysis)) {
      if (!_presentedMesh && !_releasedUnused) {
        unawaited(BodyMeshReveal.release(oldWidget.analysis.meshId));
      }
      _presentedMesh = false;
      _releasedUnused = false;
    }
  }

  @override
  void dispose() {
    _releaseUnused();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionIdentityProvider);
    final owned = widget.analysis.session?.isCurrent ?? false;
    if (!owned) _releaseUnused();
    if (owned) _presentedMesh = true;
    final rows = owned
        ? widget.analysis.summary.entries.toList()
        : <MapEntry<String, String>>[];
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
                Text(owned ? '신체분석 완료!' : '신체분석 결과',
                    style: const TextStyle(
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
                      child: owned
                          ? BodyMeshReveal(
                              key: ValueKey(widget.analysis),
                              meshId: widget.analysis.meshId)
                          : const Center(
                              child: Icon(Icons.accessibility_new_rounded,
                                  color: Color(0xFF77777F), size: 150)),
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
