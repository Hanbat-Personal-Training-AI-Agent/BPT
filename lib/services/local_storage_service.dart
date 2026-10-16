import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import '../models/workout_record_model.dart';

// Overridden in main.dart with the pre-initialized instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('SharedPreferences not initialized'),
);

final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService(ref.watch(sharedPreferencesProvider));
});

class LocalStorageService {
  final SharedPreferences _prefs;

  static const _keyUser = 'bpt_user';
  static const _keyAutoLogin = 'bpt_auto_login';
  static const _keyAuthToken = 'bpt_auth_token';
  static const _keyRefreshToken = 'bpt_refresh_token';

  // 운동 기록 캐시는 계정마다 따로 둔다. 다른 계정으로 로그인해도 이전 계정의
  // 기록이 보이지 않게 하려는 것.
  String _recordsKey(String uid) => 'bpt_workout_records_$uid';

  /// 계정 구분 없이 쓰던 예전 기록 캐시 키. 누구 기록인지 알 수 없어 지운다.
  static const _legacyRecordsKey = 'bpt_workout_records';

  /// 계정별 운동 기록 전송 대기열 키 (SyncQueueStorage 가 쓴다).
  static String syncQueueKey(String uid) => '${legacySyncQueueKey}_$uid';

  /// 계정 구분 없이 쓰던 예전 전송 대기열 키.
  static const legacySyncQueueKey = 'bpt_pending_workout_sync_queue';

  LocalStorageService(this._prefs);

  // ── User ──────────────────────────────────────────────────────────────────
  Future<void> saveUser(UserModel user) async {
    await _prefs.setString(_keyUser, user.toJsonString());
  }

  UserModel? loadUser() {
    final raw = _prefs.getString(_keyUser);
    if (raw == null) return null;
    try {
      return UserModel.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> removeUser() async {
    await _prefs.remove(_keyUser);
  }

  // ── Auto-login ────────────────────────────────────────────────────────────
  Future<void> saveAutoLogin(bool value) async {
    await _prefs.setBool(_keyAutoLogin, value);
  }

  bool loadAutoLogin() => _prefs.getBool(_keyAutoLogin) ?? false;

  // ── Auth token (서버 로그인 유지용) ───────────────────────────────────────
  Future<void> saveAuthToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _prefs.remove(_keyAuthToken);
    } else {
      await _prefs.setString(_keyAuthToken, token);
    }
  }

  String? loadAuthToken() => _prefs.getString(_keyAuthToken);

  /// 액세스 토큰(1시간)이 만료되면 새로 받는 데 쓰는 토큰 (14일).
  Future<void> saveRefreshToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _prefs.remove(_keyRefreshToken);
    } else {
      await _prefs.setString(_keyRefreshToken, token);
    }
  }

  String? loadRefreshToken() => _prefs.getString(_keyRefreshToken);

  // ── Workout Records ───────────────────────────────────────────────────────
  Future<void> saveRecords(List<WorkoutRecordModel> records,
      {required String uid}) async {
    final encoded = jsonEncode(records.map((r) => r.toJson()).toList());
    await _prefs.setString(_recordsKey(uid), encoded);
  }

  List<WorkoutRecordModel> loadRecords({required String uid}) {
    final raw = _prefs.getString(_recordsKey(uid));
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => WorkoutRecordModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addRecord(WorkoutRecordModel record,
      {required String uid}) async {
    final existing = loadRecords(uid: uid);
    // Replace if existing record ID match or insert top
    final idx = existing.indexWhere((r) => r.id == record.id);
    if (idx != -1) {
      existing[idx] = record;
    } else {
      existing.insert(0, record); // newest first
    }
    await saveRecords(existing, uid: uid);
  }

  /// 계정 구분 없이 저장돼 있던 예전 기록 캐시와 전송 대기열을 지운다 (앱 시작 시).
  Future<void> removeLegacyRecords() async {
    await _prefs.remove(_legacyRecordsKey);
    await _prefs.remove(legacySyncQueueKey);
  }

  // ── Session ───────────────────────────────────────────────────────────────
  Future<void> clearSession() async {
    await _prefs.setBool(_keyAutoLogin, false);
    await _prefs.remove(_keyAuthToken);
    await _prefs.remove(_keyRefreshToken);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_keyUser);
    await _prefs.setBool(_keyAutoLogin, false);
    await _prefs.remove(_keyAuthToken);
    await _prefs.remove(_keyRefreshToken);
  }
}
