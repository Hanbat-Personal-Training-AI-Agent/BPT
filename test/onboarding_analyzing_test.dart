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
  CancelToken? token;
  final result = Completer<CalibrationUploadReceipt>();
  @override
  Future<CalibrationUploadReceipt> upload(
    String sessionPath, {
    required CancelToken cancelToken,
    void Function(CalibrationUploadProgress)? onProgress,
  }) {
    calls++;
    token = cancelToken;
    onProgress?.call(const CalibrationUploadProgress(
        CalibrationUploadStage.uploading,
        sentBytes: 50,
        totalBytes: 100));
    return result.future;
  }
}

void main() {
  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> show(WidgetTester tester, _Uploader service,
      {String? path = '/capture/session'}) async {
    setPhoneSize(tester);
    addTearDown(service.close);
    await tester.pumpWidget(ProviderScope(overrides: [
      calibrationUploadServiceProvider.overrideWithValue(service),
    ], child: MaterialApp(home: OnboardingAnalyzingScreen(sessionPath: path))));
  }

  testWidgets('unconfigured server never uploads or fakes completion after 40s',
      (tester) async {
    final service = _Uploader(configured: false);
    await show(tester, service);
    await tester.pump(const Duration(seconds: 45));
    expect(find.byKey(const Key('upload-configuration-issue')), findsOneWidget);
    expect(find.text('사진 전송 대기'), findsOneWidget);
    expect(find.text('미연결'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('upload-calibration')))
            .onPressed,
        isNull);
    expect(service.calls, 0);
  });

  testWidgets(
      'requires user action, reports bytes, waits for acknowledgement, not analysis',
      (tester) async {
    final service = _Uploader();
    await show(tester, service);
    expect(service.calls, 0);
    await tester.tap(find.byKey(const Key('upload-calibration')));
    await tester.pump();
    expect(service.calls, 1);
    expect(find.text('파일 전송 50%'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('upload-calibration')))
            .onPressed,
        isNull);
    service.result.complete(const CalibrationUploadReceipt('session', 'job-1'));
    await tester.pumpAndSettle();
    expect(find.text('사진 전송·접수 완료'), findsOneWidget);
    expect(find.text('접수 번호: job-1'), findsOneWidget);
    expect(find.text('미연결'), findsOneWidget);
    expect(find.text('3D 체형 만들기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure keeps screen retryable, no false success',
      (tester) async {
    final service = _Uploader();
    await show(tester, service);
    await tester.tap(find.byKey(const Key('upload-calibration')));
    await tester.pump();
    service.result
        .completeError(const CalibrationUploadException('전송 실패 — 재시도'));
    await tester.pumpAndSettle();
    expect(find.text('다시 전송'), findsOneWidget);
    expect(find.byKey(const Key('upload-error')), findsOneWidget);
    expect(find.byKey(const Key('upload-receipt')), findsNothing);
  });

  testWidgets('missing session disables upload', (tester) async {
    await show(tester, _Uploader(), path: null);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('upload-calibration')))
            .onPressed,
        isNull);
  });

  testWidgets('leaving screen cancels in-flight request', (tester) async {
    final service = _Uploader();
    await show(tester, service);
    await tester.tap(find.byKey(const Key('upload-calibration')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(service.token!.isCancelled, isTrue);
    service.result.complete(const CalibrationUploadReceipt('session', 'job-1'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unconfigured server does not block home or fabricate an analysis result',
      (tester) async {
    setPhoneSize(tester);
    final service = _Uploader(configured: false);
    addTearDown(service.close);
    final router = GoRouter(initialLocation: '/scan', routes: [
      GoRoute(
          path: '/scan',
          builder: (_, __) =>
              const OnboardingAnalyzingScreen(sessionPath: '/capture/session')),
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('home destination'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      calibrationUploadServiceProvider.overrideWithValue(service),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester
        .ensureVisible(find.byKey(const Key('continue-without-analysis')));
    await tester.tap(find.byKey(const Key('continue-without-analysis')));
    await tester.pumpAndSettle();
    expect(find.text('home destination'), findsOneWidget);
    expect(service.calls, 0);
  });
}
