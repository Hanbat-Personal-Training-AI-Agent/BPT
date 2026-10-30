import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
    // Check network status
    final connectivity = await _connectivity.checkConnectivity();
    if (!_isCurrentAccount()) return WorkoutRecordModel.fromDto(metadataDto);
    final isOnline = connectivity.any((c) => c != ConnectivityResult.none);

    WorkoutRecordModel recordModel = WorkoutRecordModel.fromDto(
      metadataDto,
      isSynced: false,
    );

    // 로그인 안 했으면 누구 기록인지 알 수 없어 저장·전송하지 않는다.
    final queueStorage = _queueStorage;
    if (queueStorage == null) return recordModel;
    final uid = queueStorage.uid;

    if (isOnline) {
      try {
        // Send metadata to Spring Boot REST API
        final response = await _apiClient.post(
          '/workouts/records',
          data: metadataDto.toJson(),
        );

        if (!_isCurrentAccount()) return recordModel;
        if (response.statusCode == 200 || response.statusCode == 201) {
          final resDto = WorkoutMetadataResponseDto.fromJson(
            response.data as Map<String, dynamic>,
          );

          recordModel = recordModel.copyWith(
            isSynced: true,
            serverId: resDto.serverRecordId,
            postureScore: resDto.postureScore ?? metadataDto.postureScore,
          );

          // Save to local storage cache
          await _localStorage.addRecord(recordModel, uid: uid);
          return recordModel;
        }
      } catch (e) {
        // Network or server failure -> Fallback to Offline Queue
      }
    }

    // Offline mode or API network error: Save locally & enqueue for sync
    if (!_isCurrentAccount()) return recordModel;
    await queueStorage.enqueue(metadataDto);
    await _localStorage.addRecord(recordModel, uid: uid);

    // Trigger background sync attempt in case network recovers
    _syncNotifier.syncPendingRecords();

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
      return localRecords;
    }

    try {
      final response = await _apiClient.get('/workouts/records');
      if (!_isCurrentAccount()) return const [];
      if (response.statusCode == 200 && response.data is List) {
        final serverRecords = (response.data as List).map((json) {
          final dto =
              WorkoutMetadataRequestDto.fromJson(json as Map<String, dynamic>);
          final serverId =
              json['id']?.toString() ?? json['serverId']?.toString();
          var record = WorkoutRecordModel.fromDto(dto, isSynced: true, serverId: serverId);
          // The current server response omits stored summary metadata. Preserve matching local evidence
          // within this account; a different device/server-only record remains unknown.
          // Returned client identity is authoritative. Never attach via a reused server ID when it
          // contradicts that identity. Server-only fallback requires exactly one local mapping.
          final same = localRecords.where((r) => record.id.isNotEmpty
              ? r.id == record.id && (serverId == null || r.serverId == null || r.serverId == serverId)
              : serverId != null && r.serverId == serverId).toList();
          if (same.length == 1) {
            final local = same.single;
            record = record.copyWith(
              id: record.id.isEmpty ? local.id : record.id,
              poseMetricsSummary: record.poseMetricsSummary.isEmpty ? local.poseMetricsSummary : record.poseMetricsSummary,
              feedbackCounts: json['feedbackCounts'] == null ? local.feedbackCounts : record.feedbackCounts,
              // Preserve raw historical values if the response omitted them; none are validation.
              postureScore: json['postureScore'] == null ? local.postureScore : record.postureScore,
              correctReps: json['correctReps'] == null ? local.correctReps : record.correctReps,
              incorrectReps: json['incorrectReps'] == null ? local.incorrectReps : record.incorrectReps,
            );
          }
          return record;
        }).toList();

        // Merge un-synced local records with server records
        final unSyncedLocal = localRecords.where((r) => !r.isSynced).toList();
        final merged = [...unSyncedLocal, ...serverRecords];

        // Update local cache
        await _localStorage.saveRecords(merged, uid: uid);
        return merged;
      }
    } catch (_) {
      // Fallback to local storage if API call fails
    }

    return _isCurrentAccount() ? localRecords : const [];
  }
}

final workoutRepositoryProvider = Provider<IWorkoutRepository>((ref) {
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
    isCurrentAccount: () => active && owner != null && container.read(currentUserIdProvider) == owner.uid,
  );
});
