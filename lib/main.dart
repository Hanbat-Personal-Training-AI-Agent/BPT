import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/i18n/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/providers/profile_provider.dart';
import 'services/local_storage_service.dart';
import 'services/reminder_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local persistent storage
  final prefs = await SharedPreferences.getInstance();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const BPTApp(),
    ),
  );
}

class BPTApp extends ConsumerWidget {
  const BPTApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(appLocaleProvider);

    // 로그인 사용자의 알림 설정이 바뀌면 코리 잔소리 알림을 다시 예약한다.
    // 로그아웃하면(null) 예약을 지운다.
    ref.listen(reminderScheduleProvider, (_, next) {
      ref.read(reminderNotificationServiceProvider).sync(
            enabled: next?.$1 ?? false,
            time: next?.$2 ?? const TimeOfDay(hour: 7, minute: 0),
          );
    });

    return MaterialApp.router(
      title: 'BPT',
      debugShowCheckedModeBanner: false,
      // 모든 화면이 다크 테마를 직접 씌우고 있어 앱 전체를 다크 전용으로
      // 고정한다 (라이트/시스템 테마 분기 없음).
      theme: AppTheme.darkTheme,
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ko')],
      routerConfig: router,
    );
  }
}
