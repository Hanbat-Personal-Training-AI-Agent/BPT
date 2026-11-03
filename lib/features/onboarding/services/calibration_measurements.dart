/// Validated numeric measurements and safe provenance, never URLs/debug payloads.
/// Detection/fitting quality is retained as evidence, not an accuracy probability.
Map<String, dynamic>? calibrationMeasurements(Map<String, dynamic> result) {
  bool positive(dynamic v) => v is num && v.isFinite && v > 0;
  final bones = result['boneLengthData'];
  if (bones is! Map || bones['unit'] != 'cm') return null;
  final segments = bones['segments'];
  if (segments is! Map ||
      segments.isEmpty ||
      segments.entries.any((e) => e.key is! String || !positive(e.value))) {
    return null;
  }
  final height = result['userHeightCm'];
  if (height != null && !positive(height)) return null;
  final beta = result['smplBeta'];
  if (beta != null &&
      (beta is! List ||
          beta.length != 10 ||
          beta.any((v) => v is! num || !v.isFinite))) {
    return null;
  }
  final at = result['calibratedAt'];
  if (at != null && at is! String) return null;
  if (result['stub'] == true) return null;
  final provenance = <String, dynamic>{};
  for (final key in ['skeleton', 'pose']) {
    final value = bones[key];
    if (value is String && RegExp(r'^[a-zA-Z0-9_.-]{1,80}$').hasMatch(value)) {
      provenance[key] = value;
    }
  }
  final differs = bones['appDefinitionDiffers'];
  if (differs is List &&
      differs.every((v) => v is String && segments.containsKey(v))) {
    provenance['appDefinitionDiffers'] = List<String>.from(differs);
  }
  final quality = result['quality'];
  Map<String, dynamic>? safeQuality;
  if (quality is Map) {
    final error = quality['heightErrorCm'];
    final views = quality['perView'];
    if ((error == null || error is num && error.isFinite) &&
        views is Map &&
        views.entries.every((e) =>
            e.key is String &&
            RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(e.key as String) &&
            e.value is Map &&
            ((e.value as Map)['reprojectionErrorPx'] == null ||
                (e.value as Map)['reprojectionErrorPx'] is num &&
                    ((e.value as Map)['reprojectionErrorPx'] as num).isFinite &&
                    ((e.value as Map)['reprojectionErrorPx'] as num) >= 0))) {
      safeQuality = {
        'heightErrorCm': error,
        'perView': {
          for (final e in views.entries)
            e.key: {
              'reprojectionErrorPx': (e.value as Map)['reprojectionErrorPx']
            },
        }
      };
    }
  }
  return {
    if (result['stub'] == false) 'stub': false,
    if (result['schemaVersion'] == 1) 'schemaVersion': 1,
    if (result['bodyModel'] is String &&
        RegExp(r'^[a-zA-Z0-9_.-]{1,80}$')
            .hasMatch(result['bodyModel'] as String))
      'bodyModel': result['bodyModel'],
    if (height != null) 'userHeightCm': height,
    if (beta != null) 'smplBeta': List<num>.from(beta as List),
    'boneLengthData': {
      'unit': 'cm',
      'segments': Map<String, num>.from(segments),
      ...provenance
    },
    if (at != null) 'calibratedAt': at,
    'qualityAvailable': safeQuality != null &&
        (safeQuality['heightErrorCm'] is num ||
            (safeQuality['perView'] as Map)
                .values
                .any((v) => (v as Map)['reprojectionErrorPx'] is num)),
    if (safeQuality != null) 'quality': safeQuality,
  };
}
