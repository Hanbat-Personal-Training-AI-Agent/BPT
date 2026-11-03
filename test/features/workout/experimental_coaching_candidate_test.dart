import 'dart:convert';
import 'dart:io';
import 'package:bpt/features/workout/data/experimental_coaching_candidate.dart';
import 'package:bpt/features/workout/widgets/experimental_coaching_candidate_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> proposal(
        {int frame = 5,
        String state = 'positive_evidence',
        String meaning = 'deviation',
        String assessment = 'deviation_candidate'}) =>
    {
      'schema': 'bpt.coaching-candidate-proposal.v1',
      'proposalId': frame.toString().padLeft(64, '0'),
      'captureId': 'synthetic-fixture:test',
      'ruleId': 'pushup.camera_body_line_transfer',
      'experimentID': 'synthetic-engineering-test',
      'variant': 'floor',
      'authority': 'engineering_candidate_not_validated_form',
      'assessment': assessment,
      'predicateMeaning': meaning,
      'predicateState': state,
      'presentation': 'visual_only_no_tts',
      'delivery': 'proposed',
      'unresolvedComponents': 1,
      'source': {
        'frame': frame,
        'source_index': frame,
        'source_pts': frame * .1,
        'epoch': 1
      },
      'context': {'flush_tail': false, 'source_kind': 'synthetic_fixture'}
    };

void main() {
  test(
      'scoped deviation accepted; matched desired target and unknown never become faults',
      () {
    expect(ExperimentalCoachingCandidate.parse(proposal()), isNotNull);
    expect(
        ExperimentalCoachingCandidate.parse(proposal(
            meaning: 'desired_match', assessment: 'target_not_met_candidate')),
        isNull);
    expect(ExperimentalCoachingCandidate.parse(proposal(state: 'unknown')),
        isNull);
    expect(
        ExperimentalCoachingCandidate.parse({
          ...proposal(),
          'context': {'flush_tail': true}
        }),
        isNull);
    expect(
        ExperimentalCoachingCandidate.parse(
            {...proposal(), 'authority': 'approved_normal_form'}),
        isNull);
  });
  test(
      'stale callbacks rejected and uncertainty or lifecycle clears immediately',
      () {
    final inbox = ExperimentalCoachingCandidateInbox();
    expect(inbox.accept(proposal(frame: 5), active: true), isTrue);
    expect(inbox.accept(proposal(frame: 4), active: true), isFalse);
    expect(inbox.current?.source['frame'], 5);
    final clear = {
      'schema': 'bpt.coaching-candidate-clear.v1',
      'captureId': 'synthetic-fixture:test',
      'previousProposalId': proposal(frame: 5)['proposalId'],
      'source': {'epoch': 1, 'source_index': 6}
    };
    expect(inbox.expire(clear), isTrue);
    expect(inbox.current, isNull);
    expect(inbox.accept(proposal(frame: 5), active: true), isFalse);
    expect(inbox.accept(proposal(frame: 7), active: false), isFalse);
    expect(inbox.accept(proposal(frame: 7), active: true), isTrue);
    inbox.clear();
    expect(inbox.current, isNull);
    expect(inbox.accept(proposal(frame: 6), active: true), isFalse);
  });
  test(
      'actual native Processor source-switch packets clear old proposal before new source',
      () {
    // Exported headlessly by XCTest testExportSyntheticLiveSourceTransitionPackets.
    // This is synthetic pose input passed through the actual native Processor.
    final sequence = jsonDecode(
        File('test/fixtures/native_source_transition_20261103.json')
            .readAsStringSync()) as Map;
    expect(
        sequence['schema'], 'bpt.synthetic-native-live-source-transition.v1');
    expect(sequence['synthetic'], isTrue);
    final events = sequence['events'] as List;
    expect(events.map((e) => e['type']), ['proposal', 'clear', 'proposal']);
    final old = events[0]['payload'] as Map;
    final clear = events[1]['payload'] as Map;
    final next = events[2]['payload'] as Map;
    final inbox = ExperimentalCoachingCandidateInbox();
    expect(inbox.accept(old, active: true), isTrue);
    expect(inbox.current?.proposalId, old['proposalId']);
    expect(clear['captureId'], old['captureId']);
    expect(clear['previousProposalId'], old['proposalId']);
    expect(inbox.expire(clear), isTrue);
    expect(inbox.current, isNull);
    expect(inbox.accept(old, active: true), isFalse);
    expect(inbox.accept(next, active: true), isTrue);
    expect(inbox.current?.proposalId, next['proposalId']);
    expect(inbox.expire(clear), isFalse);
    expect(inbox.current?.proposalId, next['proposalId']);
  });
  testWidgets(
      'same product banner clearly marks synthetic scoped proposal and disappears on clear',
      (tester) async {
    final inbox = ExperimentalCoachingCandidateInbox();
    inbox.accept(proposal(), active: true);
    Widget render() => MaterialApp(
        home: Scaffold(
            body: inbox.current == null
                ? const SizedBox()
                : ExperimentalCoachingCandidateBanner(
                    candidate: inbox.current!, isKo: true)));
    await tester.pumpWidget(render());
    expect(find.text('합성 테스트 · 실험 코칭'), findsOneWidget);
    expect(find.text('몸통과 골반 정렬을 확인해 주세요.'), findsOneWidget);
    expect(find.text('관측된 부위만 비교했어요.'), findsOneWidget);
    inbox.clear();
    await tester.pumpWidget(render());
    expect(find.byType(ExperimentalCoachingCandidateBanner), findsNothing);
  });
}
