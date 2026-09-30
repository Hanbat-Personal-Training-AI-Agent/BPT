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

  String _recordsKey(String? uid) =>
      uid != null ? 'bpt_workout_records_$uid' : 'bpt_workout_records';

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

  // ── Workout Records ───────────────────────────────────────────────────────
  Future<void> saveRecords(List<WorkoutRecordModel> records,
      {String? uid}) async {
    final encoded = jsonEncode(records.map((r) => r.toJson()).toList());
    await _prefs.setString(_recordsKey(uid), encoded);
  }

  List<WorkoutRecordModel> loadRecords({String? uid}) {
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

  Future<void> addRecord(WorkoutRecordModel record, {String? uid}) async {
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

  // ── Session ───────────────────────────────────────────────────────────────
  Future<void> clearSession() async {
    await _prefs.setBool(_keyAutoLogin, false);
    await _prefs.remove(_keyAuthToken);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_keyUser);
    await _prefs.setBool(_keyAutoLogin, false);
    await _prefs.remove(_keyAuthToken);
  }
}
