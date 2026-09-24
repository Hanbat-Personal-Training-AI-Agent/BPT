import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../models/user_model.dart';

// Delegates to auth — keeps a single source of truth for the current user.
final profileUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authNotifierProvider).currentUser;
});

final notificationsEnabledProvider = StateProvider<bool>((ref) => true);

// 코리가 매일 잔소리(리마인더)를 보내는 시각. 알림 발송 로직은 아직 없고
// 지금은 표시/설정용 로컬 상태만 유지한다.
final koriReminderTimeProvider =
    StateProvider<TimeOfDay>((ref) => const TimeOfDay(hour: 7, minute: 0));

// 광고성 정보(혜택/이벤트) 수신 동의 — 기본값은 옵트인 관례에 따라 꺼짐.
final marketingConsentEnabledProvider = StateProvider<bool>((ref) => false);
