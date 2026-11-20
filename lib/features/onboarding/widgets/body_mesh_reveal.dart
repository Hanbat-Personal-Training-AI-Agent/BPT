import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Replaces the old result only with `--dart-define=BPT_MESH_REVEAL=true`.
const kBodyMeshReveal = bool.fromEnvironment('BPT_MESH_REVEAL');

/// A prepared SceneKit mesh: short entrance, rotation only, no network work.
class BodyMeshReveal extends StatefulWidget {
  const BodyMeshReveal({super.key, this.meshId});

  final String? meshId;
  static const _channel = MethodChannel('bpt/body_mesh');

  /// Parse and build geometry on the native worker queue during analysis.
  static Future<String?> prepare(Uint8List glb) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    var expired = false;
    try {
      final pending =
          _channel.invokeMethod<String>('prepare', {'glb': glb}).then((meshId) {
        if (expired) {
          release(meshId);
          return null;
        }
        return meshId;
      });
      return await pending.timeout(const Duration(seconds: 10), onTimeout: () {
        expired = true;
        return null;
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> release(String? meshId) async {
    if (meshId == null) return;
    try {
      await _channel.invokeMethod<void>('release', {'meshId': meshId});
    } on PlatformException {
      // The native cache is bounded to one pending mesh.
    } on MissingPluginException {
      // No native view on this platform.
    }
  }

  /// Scripted slow turn of the visible mesh, like a hand drag (demo recording).
  static Future<void> demoSpin({double turns = 1, double seconds = 7}) =>
      _channel.invokeMethod('spin', {'turns': turns, 'seconds': seconds});

  @override
  State<BodyMeshReveal> createState() => _BodyMeshRevealState();
}

class _BodyMeshRevealState extends State<BodyMeshReveal> {
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    BodyMeshReveal._channel.setMethodCallHandler((call) async {
      if (call.method == 'onMeshError' &&
          call.arguments == widget.meshId &&
          mounted) {
        setState(() => _unavailable = true);
      }
    });
  }

  @override
  void dispose() {
    BodyMeshReveal._channel.setMethodCallHandler(null);
    BodyMeshReveal.release(widget.meshId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable ||
        widget.meshId == null ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      return Center(
        child: Semantics(
          label: '신체 모형 미리보기 없음',
          child: const Icon(Icons.accessibility_new_rounded,
              color: Color(0xFF77777F), size: 150),
        ),
      );
    }
    return UiKitView(
      viewType: 'bpt/body_mesh',
      creationParams: {'meshId': widget.meshId},
      creationParamsCodec: const StandardMessageCodec(),
      // The drag belongs to the mesh, not to a Flutter scrollable.
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())
      },
    );
  }
}
