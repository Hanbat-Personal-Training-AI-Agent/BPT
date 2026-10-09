import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../models/user_model.dart';

// Delegates to auth — keeps a single source of truth for the current user.
final profileUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authNotifierProvider).currentUser;
});

// 알림 설정은 서버 프로필(notificationEnabled / notificationTime)에 저장한다.
// 바꿀 때는 [saveNotificationSettings] 를 쓴다. 서버 값이 없으면 켜짐 · 오전 7시.
final notificationsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(profileUserProvider)?.notificationEnabled ?? true;
});

// 코리가 매일 잔소리(리마인더)를 보내는 시각. 알림 발송 로직은 아직 없다.
final koriReminderTimeProvider = Provider<TimeOfDay>((ref) {
  return parseReminderTime(ref.watch(profileUserProvider)?.notificationTime) ??
      const TimeOfDay(hour: 7, minute: 0);
});

/// "HH:mm" → TimeOfDay. 형식이 맞지 않으면 null.
TimeOfDay? parseReminderTime(String? value) {
  final parts = value?.split(':');
  if (parts == null || parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String formatReminderTime(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

/// 알림 켜짐/시각을 현재 사용자에 반영하고 서버(PUT /users/me)에 저장한다.
void saveNotificationSettings(WidgetRef ref, {bool? enabled, TimeOfDay? time}) {
  final auth = ref.read(authNotifierProvider);
  final user = auth.currentUser;
  if (user == null) return;
  auth.updateProfile(user.copyWith(
    notificationEnabled: enabled,
    notificationTime: time == null ? null : formatReminderTime(time),
  ));
}

// 광고성 정보(혜택/이벤트) 수신 동의 — 기본값은 옵트인 관례에 따라 꺼짐.
final marketingConsentEnabledProvider = StateProvider<bool>((ref) => false);
