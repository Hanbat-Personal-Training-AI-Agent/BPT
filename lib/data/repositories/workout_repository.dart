import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart' show Options;

import '../../core/network/api_client.dart';
import '../../services/local_storage_service.dart';
import '../../services/sync_service.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../dto/workout_metadata_dto.dart';
import '../../models/workout_record_model.dart';

abstract class IWorkoutRepository {
  Future<WorkoutRecordModel> submitWorkoutRecord(
      WorkoutMetadataRequestDto metadataDto);
  Future<List<WorkoutRecordModel>> getWorkoutRecords();
}

/// 로그인한 계정 하나의 운동 기록만 다룬다. 기기 캐시와 전송 대기열도 그
/// 계정 것만 읽고 쓴다. 로그인 안 했으면 [_queueStorage]가 null 이다.
class WorkoutRepository implements IWorkoutRepository {
  final ApiClient _apiClient;
  final LocalStorageService _localStorage;
  final SyncQueueStorage? _queueStorage;
  final WorkoutSyncNotifier _syncNotifier;
  final Connectivity _connectivity;
  final bool Function() _isCurrentAccount;

  WorkoutRepository(
    this._apiClient,
    this._localStorage,
    this._queueStorage,
    this._syncNotifier,
    this._connectivity, {
    bool Function()? isCurrentAccount,
  }) : _isCurrentAccount = isCurrentAccount ?? (() => false);

  /// Submits On-Device AI metadata (Lightweight JSON with postureScore) to Spring Boot
  /// If offline or server fails, caches in local storage and queues for background sync.
  @override
  Future<WorkoutRecordModel> submitWorkoutRecord(
    WorkoutMetadataRequestDto metadataDto,
  ) async {
    WorkoutRecordModel recordModel =
        WorkoutRecordModel.fromDto(metadataDto, isSynced: false);
    final queueStorage = _queueStorage;
    if (queueStorage == null || !_isCurrentAccount()) return recordModel;
    final uid = queueStorage.uid;
    // Stage durably in the captured owner namespace before any uncertain external acknowledgement.
    // Finishing this local pair never changes account credentials or writes another user's cache.
    await queueStorage.enqueue(metadataDto);
    await _localStorage.addRecord(recordModel, uid: uid);
    if (!_isCurrentAccount()) return recordModel;
    final connectivity = await _connectivity.checkConnectivity();
    if (!_isCurrentAccount()) return recordModel;
    final isOnline = connectivity.any((c) => c != ConnectivityResult.none);

    if (isOnline) {
      try {
        // Send metadata to Spring Boot REST API
        final response = await _apiClient.post(
          '/workouts/records',
          data: metadataDto.toJson(),
          options:
              Options(extra: {ApiClient.sessionGuardKey: _isCurrentAccount}),
        );

        if (!_isCurrentAccount()) return recordModel;
        if (response.statusCode == 200 || response.statusCode == 201) {
          final resDto = WorkoutMetadataResponseDto.fromJson(
            response.data as Map<String, dynamic>,
          );

          if (!resDto.success ||
              resDto.serverRecordId.isEmpty ||
              (resDto.clientRecordId.isNotEmpty &&
                  resDto.clientRecordId != metadataDto.clientRecordId)) {
            throw ApiException('Record acknowledgement identity mismatch');
          }
          recordModel = recordModel.copyWith(
            isSynced: true,
            serverId: resDto.serverRecordId,
            postureScore: resDto.postureScore ?? metadataDto.postureScore,
          );

          await queueStorage.remove(metadataDto.clientRecordId);
          // Complete acknowledged bookkeeping in the captured owner namespace only.
          await _localStorage.addRecord(recordModel, uid: uid);
          return recordModel;
        }
      } catch (e) {
        // Network or server failure -> Fallback to Offline Queue
      }
    }

    // No acknowledgement does not mean no server commit. Keep the staged ID for idempotent retry.
    if (!_isCurrentAccount()) return recordModel;
    // Trigger background sync attempt in case network recovers
    if (_isCurrentAccount()) _syncNotifier.syncPendingRecords();

    return recordModel;
  }

  /// Fetches workout records merging online Spring Boot records with offline local records
  @override
  Future<List<WorkoutRecordModel>> getWorkoutRecords() async {
    final uid = _queueStorage?.uid;
    if (uid == null || !_isCurrentAccount()) return const [];
    final localRecords = _localStorage.loadRecords(uid: uid);

    final connectivity = await _connectivity.checkConnectivity();
    final isOnline = connectivity.any((c) => c != ConnectivityResult.none);
    if (!_isCurrentAccount()) return const [];

    if (!isOnline) {
      return _localStorage.loadRecords(uid: uid);
    }

    try {
      final response = await _apiClient.get('/workouts/records',
          options:
              Options(extra: {ApiClient.sessionGuardKey: _isCurrentAccount}));
      if (!_isCurrentAccount()) return const [];
      if (response.statusCode == 200 && response.data is List) {
        // A submit may have staged data while this GET was pending. Never overwrite it from an old snapshot.
        final latestLocal = _localStorage.loadRecords(uid: uid);
        final serverRecords = (response.data as List).map((json) {
          final dto =
              WorkoutMetadataRequestDto.fromJson(json as Map<String, dynamic>);
          final serverId =
              json['id']?.toString() ?? json['serverId']?.toString();
          var record = WorkoutRecordModel.fromDto(dto,
              isSynced: true, serverId: serverId);
          // The current server response omits stored summary metadata. Preserve matching local evidence
          // within this account; a different device/server-only record remains unknown.
          // Returned client identity is authoritative. Never attach via a reused server ID when it
          // contradicts that identity. Server-only fallback requires exactly one local mapping.
          final same = latestLocal
              .where((r) => record.id.isNotEmpty
                  ? r.id == record.id &&
                      (serverId == null ||
                          r.serverId == null ||
                          r.serverId == serverId)
                  : serverId != null && r.serverId == serverId)
              .toList();
          if (same.length == 1) {
            final local = same.single;
            record = record.copyWith(
              id: record.id.isEmpty ? local.id : record.id,
              poseMetricsSummary: record.poseMetricsSummary.isEmpty
                  ? local.poseMetricsSummary
                  : record.poseMetricsSummary,
              feedbackCounts: json['feedbackCounts'] == null
                  ? local.feedbackCounts
                  : record.feedbackCounts,
              // Preserve raw historical values if the response omitted them; none are validation.
              postureScore: json['postureScore'] == null
                  ? local.postureScore
                  : record.postureScore,
              correctReps: json['correctReps'] == null
                  ? local.correctReps
                  : record.correctReps,
              incorrectReps: json['incorrectReps'] == null
                  ? local.incorrectReps
                  : record.incorrectReps,
            );
          }
          return record;
        }).toList();

        bool sameRecord(WorkoutRecordModel a, WorkoutRecordModel b) =>
            a.id.isNotEmpty &&
            a.id == b.id &&
            (a.serverId == null ||
                b.serverId == null ||
                a.serverId == b.serverId);
        bool changedSinceRequest(WorkoutRecordModel local) {
          if (local.id.isEmpty &&
              (local.serverId == null || local.serverId!.isEmpty)) {
            return false;
          }
          final before = localRecords
              .where((old) => local.id.isNotEmpty
                  ? old.id == local.id
                  : old.id.isEmpty && old.serverId == local.serverId)
              .toList();
          return before.length != 1 ||
              jsonEncode(before.single.toJson()) != jsonEncode(local.toJson());
        }

        final protected = latestLocal
            .where((r) => !r.isSynced || changedSinceRequest(r))
            .toList();
        // Retain only pending or concurrently added/changed local identities. Unchanged synced history
        // absent from the response is not resurrected. A stale GET cannot erase a newer submit ACK.
        final visibleServer = serverRecords
            .where((remote) => !protected.any((local) =>
                local.id == remote.id &&
                (changedSinceRequest(local) || !sameRecord(local, remote))))
            .toList();
        final merged = [
          ...protected.where((local) =>
              !visibleServer.any((remote) => sameRecord(local, remote))),
          ...visibleServer,
        ];

        // Update local cache
        await _localStorage.saveRecords(merged, uid: uid);
        return _isCurrentAccount()
            ? _localStorage.loadRecords(uid: uid)
            : const [];
      }
    } catch (_) {
      // Fallback to local storage if API call fails
    }

    return _isCurrentAccount() ? _localStorage.loadRecords(uid: uid) : const [];
  }
}

final workoutRepositoryProvider = Provider<IWorkoutRepository>((ref) {
  ref.watch(authSessionIdentityProvider);
  final lease = ref.read(authNotifierProvider).captureSession();
  final owner = ref.watch(syncQueueStorageProvider);
  final container = ref.container;
  var active = true;
  ref.onDispose(() => active = false);
  return WorkoutRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStorageServiceProvider),
    ref.watch(syncQueueStorageProvider),
    ref.watch(workoutSyncProvider.notifier),
    ref.watch(connectivityProvider),
    isCurrentAccount: () =>
        active &&
        owner != null &&
        lease != null &&
        lease.isCurrent &&
        lease.userId == owner.uid &&
        container.read(currentUserIdProvider) == owner.uid,
  );
});
