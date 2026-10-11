import 'dart:async';

import 'package:bpt/features/onboarding/screens/onboarding_analyzing_screen.dart';
import 'package:bpt/features/onboarding/services/calibration_upload_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Uploader extends CalibrationUploadService {
  _Uploader({bool configured = true})
      : super(
            config: configured
                ? const CalibrationUploadConfig(
                    apiBaseUrl: 'https://api.example.test',
                    storageHosts: ['photos.example.test'],
                  )
                : const CalibrationUploadConfig(),
            tokenProvider: () async => 'token');
  int calls = 0;
  String? path;
  final result = Completer<CalibrationUploadReceipt>();
  @override
  Future<CalibrationUploadReceipt> upload(
    String sessionPath, {
    required CancelToken cancelToken,
    void Function(CalibrationUploadProgress)? onProgress,
  }) {
    calls++;
    path = sessionPath;
    return result.future;
  }
}

void main() {
  Future<void> show(WidgetTester tester, _Uploader service,
      {String? path = '/capture/session'}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(service.close);
    final router = GoRouter(initialLocation: '/analyzing', routes: [
      GoRoute(
          path: '/analyzing',
          builder: (_, __) => OnboardingAnalyzingScreen(sessionPath: path)),
      GoRoute(
          path: '/onboarding/result',
          builder: (_, __) => const Scaffold(body: Text('result destination'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      calibrationUploadServiceProvider.overrideWithValue(service),
    ], child: MaterialApp.router(routerConfig: router)));
  }

  testWidgets('uploads right away without a button', (tester) async {
    final service = _Uploader();
    await show(tester, service);
    await tester.pump();
    expect(service.calls, 1);
    expect(service.path, '/capture/session');
    expect(find.text('40초 정도 걸려.\n조금만 기다려줘!'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    service.result.complete(const CalibrationUploadReceipt('session', 'job-1'));
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
  });

  testWidgets('goes to the result after the animation once upload is accepted',
      (tester) async {
    final service = _Uploader();
    await show(tester, service);
    await tester.pump(const Duration(seconds: 10));
    service.result.complete(const CalibrationUploadReceipt('session', 'job-1'));
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('result destination'), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('result destination'), findsOneWidget);
  });

  testWidgets('waits for an upload still running after 40s', (tester) async {
    final service = _Uploader();
    await show(tester, service);
    await tester.pump(const Duration(seconds: 45));
    await tester.pump();
    expect(find.text('result destination'), findsNothing);
    service.result.complete(const CalibrationUploadReceipt('session', 'job-1'));
    await tester.pumpAndSettle();
    expect(find.text('result destination'), findsOneWidget);
  });

  testWidgets('a failed upload still continues to the result', (tester) async {
    final service = _Uploader();
    await show(tester, service);
    service.result
        .completeError(const CalibrationUploadException('전송 실패 — 재시도'));
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(find.text('result destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfigured server skips the upload and continues',
      (tester) async {
    final service = _Uploader(configured: false);
    await show(tester, service);
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.text('result destination'), findsOneWidget);
  });

  testWidgets('missing session skips the upload and continues',
      (tester) async {
    final service = _Uploader();
    await show(tester, service, path: null);
    await tester.pump(const Duration(seconds: 41));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.text('result destination'), findsOneWidget);
  });
}
