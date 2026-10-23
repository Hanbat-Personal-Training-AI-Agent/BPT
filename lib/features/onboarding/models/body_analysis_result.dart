/// Analysis values and an in-memory native mesh prepared before navigation.
class BodyAnalysisResult {
  const BodyAnalysisResult({this.values = const {}, this.meshId});

  final Map<String, dynamic> values;
  final String? meshId;

  /// Only measured fields are shown. Limb lengths require both segments.
  Map<String, String> get summary {
    final rows = <String, String>{};
    double? positive(dynamic value) =>
        value is num && value.isFinite && value > 0 ? value.toDouble() : null;
    void add(String label, double? value, String unit) {
      if (value != null) rows[label] = '${value.toStringAsFixed(1)} $unit';
    }

    add('키', positive(values['userHeightCm']), 'cm');
    add('몸무게', positive(values['weightKg']), 'kg');
    final bones = values['boneLengthData'];
    if (bones is! Map || bones['unit'] != 'cm') return rows;
    final segments = bones['segments'];
    if (segments is! Map) return rows;
    double? sum(String first, String second) {
      final a = positive(segments[first]);
      final b = positive(segments[second]);
      return a == null || b == null ? null : a + b;
    }

    add('어깨 너비', positive(segments['shoulder_width']), 'cm');
    for (final side in {'left': '왼쪽', 'right': '오른쪽'}.entries) {
      add(
          '${side.value} 팔 길이',
          sum('${side.key}_shoulder-${side.key}_elbow',
              '${side.key}_elbow-${side.key}_wrist'),
          'cm');
      add(
          '${side.value} 다리 길이',
          sum('${side.key}_hip-${side.key}_knee',
              '${side.key}_knee-${side.key}_ankle'),
          'cm');
    }
    add('몸통 길이', sum('pelvis-spine', 'spine-thorax'), 'cm');
    return rows;
  }
}
