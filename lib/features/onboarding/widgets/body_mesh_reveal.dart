import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../services/calibration_upload_service.dart';

/// Analyzing → 3D body reveal → result. Off by default so the teammates' flow stays as it is
/// (docs/handoff/teammate_requests.md §10); turn on with `--dart-define=BPT_MESH_REVEAL=true`.
const kBodyMeshReveal = bool.fromEnvironment('BPT_MESH_REVEAL');

/// The user's own SMPL body (server `result.modelGlbUrl`) in a native SceneKit view
/// (`ios/Runner/NativePose/BodyMesh`): card-style entrance with a shine sweep, then a slow
/// auto-rotation until touched. Drag turns it (yaw free, pitch ±15°); no zoom, no pan.
///
/// Waits for the fit job ([waitFor]), downloads the GLB and calls [onUnavailable] once when
/// there is no mesh to show (failed or slow job, no network, not iOS).
class BodyMeshReveal extends ConsumerStatefulWidget {
  const BodyMeshReveal({
    super.key,
    required this.jobId,
    required this.onUnavailable,
    this.onRevealed,
    this.waitFor = const Duration(minutes: 3),
  });

  final String jobId;
  final VoidCallback onUnavailable;

  /// When the mesh starts its entrance.
  final VoidCallback? onRevealed;
  final Duration waitFor;

  static const _channel = MethodChannel('bpt/body_mesh');

  /// Scripted slow turn of the visible mesh, like a hand drag (demo recording).
  static Future<void> demoSpin({double turns = 1, double seconds = 7}) =>
      _channel.invokeMethod('spin', {'turns': turns, 'seconds': seconds});

  @override
  ConsumerState<BodyMeshReveal> createState() => _BodyMeshRevealState();
}

class _BodyMeshRevealState extends ConsumerState<BodyMeshReveal> {
  final _cancel = CancelToken();
  Uint8List? _glb;
  int _progress = 0;
  bool _gaveUp = false;

  @override
  void initState() {
    super.initState();
    BodyMeshReveal._channel.setMethodCallHandler((call) async {
      if (call.method == 'onMeshError') _giveUp();
    });
    _load();
  }

  Future<void> _load() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return _giveUp();
    final service = ref.read(calibrationUploadServiceProvider);
    final deadline = DateTime.now().add(widget.waitFor);
    while (mounted && DateTime.now().isBefore(deadline)) {
      try {
        final job = await service.fetchJob(widget.jobId, cancelToken: _cancel);
        if (job.status == 'failed') break;
        final url = job.result?['modelGlbUrl'];
        if (job.status == 'done') {
          if (url is! String) break;
          final glb = await service.fetchModel(url, cancelToken: _cancel);
          if (!mounted) return;
          setState(() => _glb = glb);
          widget.onRevealed?.call();
          return;
        }
        if (mounted) setState(() => _progress = job.progressRate);
      } on DioException {
        return; // cancelled: the widget is gone
      } on CalibrationUploadException catch (error) {
        debugPrint('[BodyMesh] ${error.message}');
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    _giveUp();
  }

  void _giveUp() {
    if (!mounted || _gaveUp) return;
    _gaveUp = true;
    widget.onUnavailable();
  }

  @override
  void dispose() {
    _cancel.cancel();
    BodyMeshReveal._channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glb = _glb;
    if (glb == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.green)),
            const SizedBox(height: 14),
            Text('3D 몸 만드는 중 $_progress%',
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }
    return UiKitView(
      viewType: 'bpt/body_mesh',
      creationParams: {'glb': glb},
      creationParamsCodec: const StandardMessageCodec(),
      // The drag belongs to the mesh, not to any Flutter scrollable above it.
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())
      },
    );
  }
}
