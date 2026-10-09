import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 코리 잔소리: 프로필에서 정한 시각에 매일 한 번 울리는 기기 알림.
///
/// 서버 없이 기기에서 예약한다. iOS 전용. 알림 켜짐/시각이 바뀔 때마다 [sync]로 다시 예약한다.
class ReminderNotificationService {
  ReminderNotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _reminderId = 1;

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  Future<void> _init() async {
    tz_data.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        // 권한은 사용자가 알림을 켤 때 묻는다.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  }

  /// 알림을 켜면 매일 [time]에 예약하고, 끄면 예약을 지운다.
  Future<void> sync({required bool enabled, required TimeOfDay time}) async {
    if (kIsWeb) return;
    try {
      await (_ready ??= _init());
      await _plugin.cancel(id: _reminderId);
      if (!enabled || !await _requestPermission()) return;

      await _plugin.zonedSchedule(
        id: _reminderId,
        title: '코리가 기다리고 있어!',
        body: '오늘 운동할 시간이야. 자세는 내가 봐줄게!',
        scheduledDate: _nextInstanceOf(time),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
        ),
        // 필수 인자라 넣지만 iOS 에서는 쓰이지 않는다.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('[Reminder] 알림 예약 실패: $e');
    }
  }

  Future<bool> _requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios == null) return false;
    return await ios.requestPermissions(alert: true, sound: true) ?? false;
  }

  tz.TZDateTime _nextInstanceOf(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }
}

final reminderNotificationServiceProvider =
    Provider<ReminderNotificationService>((ref) => ReminderNotificationService());
