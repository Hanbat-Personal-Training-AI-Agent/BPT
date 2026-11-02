import 'package:flutter/material.dart';
import '../data/experimental_coaching_candidate.dart';

/// Visible only after an explicit native experiment emits a validated proposal.
class ExperimentalCoachingCandidateBanner extends StatelessWidget {
  const ExperimentalCoachingCandidateBanner(
      {super.key, required this.candidate, required this.isKo});
  final ExperimentalCoachingCandidate candidate;
  final bool isKo;
  @override
  Widget build(BuildContext context) => Semantics(
      liveRegion: true,
      child: Material(
          color: const Color(0xff243342),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        candidate.isSynthetic
                            ? (isKo
                                ? '합성 테스트 · 실험 코칭'
                                : 'Synthetic test · experimental coaching')
                            : (isKo
                                ? '실험 코칭 · 선택한 기준 비교'
                                : 'Experimental coaching · selected criteria'),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(candidate.cue(isKo: isKo),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    if (candidate.unresolvedComponents > 0)
                      Text(
                          isKo
                              ? '관측된 부위만 비교했어요.'
                              : 'Only observed components were compared.',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11))
                  ]))));
}
