// Checks capture folders against the app uploader's own validation (CalibrationBundle.load).
//
//   CALIBRATION_BUNDLES=<session dir>[:<session dir>...] flutter test tool/calibration_bundle_check_test.dart
import 'dart:io';

import 'package:bpt/features/onboarding/services/calibration_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final paths = (Platform.environment['CALIBRATION_BUNDLES'] ?? '')
      .split(':')
      .where((path) => path.isNotEmpty);
  for (final path in paths) {
    test('app accepts $path', () async {
      final bundle = await CalibrationBundle.load(path);
      expect(bundle.files.map((file) => file.name), [
        'manifest.json',
        'view_front.jpg',
        'view_rightfront.jpg',
        'view_back.jpg',
        'view_leftfront.jpg',
      ]);
      // ignore: avoid_print
      print('${bundle.sessionId}: ${bundle.totalBytes} bytes');
    });
  }
}
