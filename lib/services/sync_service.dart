import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart' show Response, Options;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';
import '../data/dto/workout_metadata_dto.dart';
import '../features/auth/providers/auth_provider.dart';
import 'local_storage_service.dart';

/// Sync Status State for Riverpod UI feedback
class SyncState {
  final bool isSyncing;
  final int pendingCount;
  final String? lastSyncError;
  final DateTime? lastSyncedAt;
  final Map<String, String> recordErrors;

  const SyncState({
    this.isSyncing = false,
    this.pendingCount = 0,
    this.lastSyncError,
    this.lastSyncedAt,
    this.recordErrors = const {},
  });

  SyncState copyWith({
    bool? isSyncing,
    int? pendingCount,
    String? lastSyncError,
    DateTime? lastSyncedAt,
    Map<String, String>? recordErrors,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncError: lastSyncError,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      recordErrors: recordErrors ?? this.recordErrors,
    );
  }
}

/// Offline Pending Queue Storage using SharedPreferences
/// 전송 대기열은 계정마다 따로 둔다. 다른 계정으로 로그인했을 때 이전 계정의
/// 기록이 새 계정으로 전송되지 않게 하려는 것.
class SyncQueueStorage {
  final SharedPreferences _prefs;

  /// 대기열 주인 (현재 로그인한 사용자 ID).
  final String uid;

  String get _queueKey => LocalStorageService.syncQueueKey(uid);

  SyncQueueStorage(this._prefs, this.uid);

  String get _errorsKey => 'bpt_workout_sync_errors_$uid';
  Map<String, String> getFailures() {
    try {
      final raw = _prefs.getString(_errorsKey);
      return raw == null
          ? {}
          : Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> recordFailure(String id, String error) async {
    await _prefs.setString(
        _errorsKey, jsonEncode({...getFailures(), id: error}));
  }

  Future<void> clearFailure(String id) async {
    final failures = getFailures()..remove(id);
    await _prefs.setString(_errorsKey, jsonEncode(failures));
  }

  List<WorkoutMetadataRequestDto> getQueue() {
    final raw = _prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List list = jsonDecode(raw);
      return list
          .map((item) =>
              WorkoutMetadataRequestDto.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> enqueue(WorkoutMetadataRequestDto dto) async {
    final queue = getQueue();
    // Avoid duplicate client IDs in queue
    queue.removeWhere((item) => item.clientRecordId == dto.clientRecordId);
    queue.add(dto);
    await _saveQueue(queue);
    await clearFailure(dto.clientRecordId);
  }

  /// 같은 자리에서 기록을 바꾼다 (보내는 순서 유지).
  Future<void> replace(
      String clientRecordId, WorkoutMetadataRequestDto dto) async {
    final queue = getQueue();
    final index =
        queue.indexWhere((item) => item.clientRecordId == clientRecordId);
    if (index == -1) return;
    queue[index] = dto;
    await _saveQueue(queue);
    await clearFailure(clientRecordId);
  }

  Future<void> remove(String clientRecordId) async {
    final queue = getQueue();
    queue.removeWhere((item) => item.clientRecordId == clientRecordId);
    await _saveQueue(queue);
    await clearFailure(clientRecordId);
  }

  Future<void> clear() async {
    await _prefs.remove(_queueKey);
    await _prefs.remove(_errorsKey);
  }

  Future<void> _saveQueue(List<WorkoutMetadataRequestDto> queue) async {
    final jsonList = queue.map((e) => e.toJson()).toList();
    await _prefs.setString(_queueKey, jsonEncode(jsonList));
  }
}

/// 로그인 안 했으면 null.
final syncQueueStorageProvider = Provider<SyncQueueStorage?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return SyncQueueStorage(ref.watch(sharedPreferencesProvider), uid);
});

/// 네트워크 연결 상태 (테스트에서 바꿔 끼울 수 있게 Provider로 둔다).
final connectivityProvider = Provider<Connectivity>((_) => Connectivity());

/// Offline-First Synchronization Engine
class WorkoutSyncNotifier extends StateNotifier<AsyncValue<SyncState>> {
  final ApiClient _apiClient;

  /// 로그인 안 했으면 null 이고 아무것도 보내지 않는다.
  final SyncQueueStorage? _queueStorage;
  final LocalStorageService _localStorage;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// 지금 로그인한 계정이 이 대기열의 주인인지. 아니면 보내지 않는다.
  /// (로그아웃·계정 변경 직후에는 이 객체가 잠깐 남아 있을 수 있고, 그때
  /// 요청에는 새 계정의 토큰이 붙는다)
  final bool Function() _isCurrentAccount;
  Future<bool>? _inFlight;
  bool get _ownsSession => mounted && _isCurrentAccount();

  WorkoutSyncNotifier(
    this._apiClient,
    this._queueStorage,
    this._localStorage,
    this._connectivity, {
    bool Function()? isCurrentAccount,
  })  : _isCurrentAccount = isCurrentAccount ?? (() => false),
        super(const AsyncValue.data(SyncState())) {
    _initConnectivityListener();
    _updatePendingCount();
  }

  void _initConnectivityListener() {
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        // Trigger auto-sync when network connectivity is restored
        syncPendingRecords();
      }
    });
  }

  List<WorkoutMetadataRequestDto> _queue() =>
      _queueStorage?.getQueue() ?? const [];

  void _updatePendingCount() {
    if (!_ownsSession) return;
    final count = _queue().length;
    final current = state.value ?? const SyncState();
    final errors = _queueStorage?.getFailures() ?? const <String, String>{};
    state = AsyncValue.data(current.copyWith(
        pendingCount: count,
        recordErrors: errors,
        lastSyncError: errors.isEmpty ? null : errors.values.first));
  }

  /// Adds an un-synced workout record to offline queue
  Future<void> queueOfflineRecord(WorkoutMetadataRequestDto dto) async {
    if (!_ownsSession) return;
    await _queueStorage?.enqueue(dto);
    if (!_ownsSession) return;
    _updatePendingCount();
  }

  /// Concurrent triggers share the same owner-scoped drain; a row is posted at most once per run.
  Future<bool> syncPendingRecords() {
    final pending = _inFlight;
    if (pending != null) return pending;
    late final Future<bool> run;
    run = _drain().whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
    _inFlight = run;
    return run;
  }

  Future<bool> _drain() async {
    final storage = _queueStorage;
    if (!_ownsSession || storage == null) return false;
    final currentQueue = _queue();
    if (currentQueue.isEmpty) {
      _updatePendingCount();
      return storage.getFailures().isEmpty;
    }
    final before = state.value ?? const SyncState();
    state =
        AsyncValue.data(before.copyWith(isSyncing: true, lastSyncError: null));
    String? lastError;
    for (var dto in currentQueue) {
      if (!_ownsSession) return false;
      try {
        Response response;
        try {
          response = await _post(dto);
        } on ApiException catch (e) {
          if (!_ownsSession) return false;
          if (e.code != ApiClient.sessionAccessDenied) rethrow;
          dto = await _renumber(storage, dto);
          if (!_ownsSession) {
            return false; // No retry with a new account token after the await.
          }
          response = await _post(dto);
        }
        if (!_ownsSession) return false;
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw ApiException('Unexpected sync response',
              statusCode: response.statusCode);
        }
        final result = WorkoutMetadataResponseDto.fromJson(
            response.data as Map<String, dynamic>);
        if (!result.success ||
            result.serverRecordId.isEmpty ||
            (result.clientRecordId.isNotEmpty &&
                result.clientRecordId != dto.clientRecordId)) {
          throw ApiException('Sync acknowledgement identity mismatch');
        }
        await storage.remove(dto.clientRecordId);
        // A validated acknowledgement may finish bookkeeping only in its captured owner cache.
        await _markLocalRecordSynced(dto.clientRecordId, result.serverRecordId);
        if (!_ownsSession) return false;
      } catch (e) {
        if (!_ownsSession) return false;
        if (e is ApiException && (e.statusCode == 400 || e.statusCode == 422)) {
          lastError =
              'Record ${dto.clientRecordId} rejected (${e.statusCode}/${e.code ?? 'invalid input'}); retained for review.';
          await storage.recordFailure(dto.clientRecordId, lastError);
          if (!_ownsSession) return false;
          continue; // Retain this row, but do not starve healthy rows behind it.
        }
        lastError = 'Sync interrupted; queued records retained.';
        break; // Network/auth/server failures require a later retry, not a busy loop.
      }
    }
    if (!_ownsSession) return false;
    final count = _queue().length;
    state = AsyncValue.data(SyncState(
        isSyncing: false,
        pendingCount: count,
        recordErrors: storage.getFailures(),
        lastSyncError: count > 0
            ? lastError ?? 'Pending records retained for review.'
            : null,
        lastSyncedAt: count == 0 ? DateTime.now() : before.lastSyncedAt));
    return count == 0;
  }

  Future<Response> _post(WorkoutMetadataRequestDto dto) {
    if (!_ownsSession) {
      throw ApiException('Account session changed',
          code: ApiClient.sessionChangedCode);
    }
    return _apiClient.post('/workouts/records/sync',
        data: dto.toJson(),
        options:
            Options(extra: {ApiClient.sessionGuardKey: () => _ownsSession}));
  }

  /// 대기열과 기기 기록의 번호를 새 번호로 바꾼다.
  Future<WorkoutMetadataRequestDto> _renumber(
      SyncQueueStorage queueStorage, WorkoutMetadataRequestDto dto) async {
    final renumbered = dto.withClientRecordId(newClientRecordId());
    await queueStorage.replace(dto.clientRecordId, renumbered);
    final records = _localStorage.loadRecords(uid: queueStorage.uid);
    final index = records.indexWhere((r) => r.id == dto.clientRecordId);
    if (index != -1) {
      records[index] = records[index].copyWith(id: renumbered.clientRecordId);
      await _localStorage.saveRecords(records, uid: queueStorage.uid);
    }
    return renumbered;
  }

  Future<void> _markLocalRecordSynced(
      String clientRecordId, String serverRecordId) async {
    final uid = _queueStorage?.uid;
    if (uid == null) return;
    final records = _localStorage.loadRecords(uid: uid);
    final index = records.indexWhere((r) => r.id == clientRecordId);
    if (index != -1) {
      final updated = records[index].copyWith(
        isSynced: true,
        serverId: serverRecordId,
      );
      records[index] = updated;
      await _localStorage.saveRecords(records, uid: uid);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}

final workoutSyncProvider =
    StateNotifierProvider<WorkoutSyncNotifier, AsyncValue<SyncState>>((ref) {
  ref.watch(authSessionIdentityProvider);
  final lease = ref.read(authNotifierProvider).captureSession();
  final queueStorage = ref.watch(syncQueueStorageProvider);
  // 이 Provider가 다시 만들어진 뒤에도 안전하게 읽도록 container 로 읽는다.
  final container = ref.container;
  return WorkoutSyncNotifier(
    ref.watch(apiClientProvider),
    queueStorage,
    ref.watch(localStorageServiceProvider),
    ref.watch(connectivityProvider),
    isCurrentAccount: () =>
        queueStorage != null &&
        lease != null &&
        lease.isCurrent &&
        lease.userId == queueStorage.uid &&
        container.read(currentUserIdProvider) == queueStorage.uid,
  );
});
