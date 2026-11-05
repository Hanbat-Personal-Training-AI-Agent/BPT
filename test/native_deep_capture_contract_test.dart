// Opt-in local private evidence, never a network/model or whole-E2E test.
import 'dart:convert';
import 'dart:io';

import 'package:bpt/features/workout/data/deep_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

const packagePath = String.fromEnvironment('BPT_NATIVE_CAPTURE_PACKAGE');
const evidencePath = String.fromEnvironment('BPT_NATIVE_CAPTURE_EVIDENCE');
const existingJobPath =
    String.fromEnvironment('BPT_EXISTING_DEEP_JOB_EVIDENCE');

Future<String> localSha(File file) async {
  final result = await Process.run('/usr/bin/shasum', ['-a', '256', file.path]);
  expect(result.exitCode, 0);
  return (result.stdout as String).split(' ').first;
}

void main() {
  test(
      'official fromSet adds UI exercise context without changing native evidence',
      () {
    final native = <String, dynamic>{
      'schemaVersion': 1,
      'sessionId': 'synthetic_context_contract',
      'timebase': 'video_ms',
      'reps': [
        {
          'repIndex': 1,
          'startMs': 100,
          'endMs': 500,
          'side': 'left',
          'onDeviceWarnings': <String>[]
        }
      ],
    };
    final original = jsonEncode(native);
    final capture = DeepAnalysisCapture.fromSet({
      'videoLocalPath': '/local/synthetic_contract_only.mp4',
      'deepAnalysis': native,
    }, 'barbell-row');
    expect(capture, isNotNull);
    expect(capture!.manifest, {...native, 'exerciseId': 'barbell-row'});
    expect(capture.manifest['reps'], native['reps']);
    expect(jsonEncode(native), original);
    expect(native.containsKey('exerciseId'), isFalse);
  });

  test(
      'actual native receipt reaches current capture parser without changing observations',
      () async {
    final verified =
        jsonDecode(File('$packagePath/verification.json').readAsStringSync())
            as Map;
    final record =
        jsonDecode(File('$packagePath/capture.json').readAsStringSync()) as Map;
    final manifest =
        jsonDecode(File('$packagePath/reps.json').readAsStringSync()) as Map;
    final original = jsonDecode(File(evidencePath).readAsStringSync()) as Map;
    expect(verified['status'], 'exact_video_and_manifest_verified');
    expect(
        await localSha(File(evidencePath)), verified['captureEvidenceSha256']);
    final capture =
        DeepAnalysisCapture.fromSet(record, manifest['exerciseId'] as String);
    expect(capture, isNotNull);
    final originalRecording = (original['recording'] ?? original) as Map;
    final originalManifest = originalRecording['manifest'] as Map;
    expect(record['deepAnalysis'], originalManifest);
    expect(capture!.manifest['reps'], originalManifest['reps']);
    expect(capture.manifest,
        {...originalManifest, 'exerciseId': manifest['exerciseId']});
    expect(capture.manifest, manifest);
    expect(capture.manifest['reps'],
        hasLength((originalManifest['reps'] as List).length));
    expect(capture.manifest['timebase'], 'video_ms');
    expect(capture.exerciseId, 'barbell-row');
    expect(capture.sessionId, manifest['sessionId']);
    final video = File(capture.videoPath);
    expect(video.existsSync(), isTrue);
    expect(await localSha(video), verified['copiedVideoSha256']);
    expect(verified['remoteTransportAllowed'], isFalse);
    expect(verified['onDeviceObservationsChanged'], isFalse);
    expect(verified['newInferenceExecuted'], isFalse);
    expect(verified['serviceReportProduced'], isFalse);
  }, skip: packagePath.isEmpty || evidencePath.isEmpty);

  test(
      'prior actual owner job parses independently and is not this native row input',
      () {
    final raw = jsonDecode(File(existingJobPath).readAsStringSync())
        as Map<String, dynamic>;
    final job = DeepAnalysisJob.fromJson(raw);
    final current =
        jsonDecode(File('$packagePath/reps.json').readAsStringSync()) as Map;
    expect(job.status, 'done');
    expect(job.result!['report']['exerciseId'], 'squat');
    expect(job.result!['report']['reps'], hasLength(4));
    expect(current['exerciseId'], 'barbell-row');
    expect(current['reps'], isNotEmpty);
    expect(job.result!['report']['exerciseId'], isNot(current['exerciseId']));
    // No source/video identity is inferred from a parsed done job or its signed URLs.
  }, skip: packagePath.isEmpty || existingJobPath.isEmpty);

  test('invalid capture identity and malformed done job stay rejected', () {
    expect(
        DeepAnalysisCapture.fromSet({
          'videoLocalPath': 'local.mp4',
          'deepAnalysis': {
            'sessionId': 'bad/session',
            'reps': [{}]
          }
        }, 'barbell-row'),
        isNull);
    expect(
        () => DeepAnalysisJob.fromJson({
              'status': 'done',
              'result': {
                'report': {'schemaVersion': 1, 'reps': []}
              }
            }),
        throwsFormatException);
  });
}
