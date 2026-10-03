import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A-pose body outlines used as the calibration camera guide.
///
/// The outlines come from the neutral SMPL body posed in the A-pose we ask the
/// user to hold, projected at each capture yaw and reduced to its outer contour
/// (`scripts/build_calibration_silhouettes.py` writes the asset). Drawing only the
/// contour keeps the camera visible underneath.
class CalibrationSilhouettes {
  const CalibrationSilhouettes._(this._views);

  final Map<String, CalibrationSilhouette> _views;

  static const _assetPath = 'assets/calibration/silhouettes.json';
  static CalibrationSilhouettes? _cache;

  static Future<CalibrationSilhouettes> load() async {
    if (_cache != null) return _cache!;
    final raw = json.decode(await rootBundle.loadString(_assetPath))
        as Map<String, dynamic>;
    final views = (raw['views'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, CalibrationSilhouette.fromJson(value as Map<String, dynamic>)),
    );
    return _cache = CalibrationSilhouettes._(views);
  }

  CalibrationSilhouette? operator [](String? view) => _views[view ?? 'front'];
}

class CalibrationSilhouette {
  const CalibrationSilhouette(this.points, this.widthOverHeight);

  /// Normalized by body height: y from 0 (head top) to 1 (feet), x centred on 0.5.
  final List<Offset> points;
  final double widthOverHeight;

  factory CalibrationSilhouette.fromJson(Map<String, dynamic> json) => CalibrationSilhouette(
        [
          for (final point in json['points'] as List)
            Offset((point[0] as num).toDouble(), (point[1] as num).toDouble()),
        ],
        (json['widthOverHeight'] as num).toDouble(),
      );
}

/// Draws the outline for [view], mirrored so it lines up with the mirrored preview.
///
/// [progress] fills the outline clockwise from the feet while the user holds still,
/// so the wait is visible without a countdown number.
class CalibrationSilhouettePainter extends CustomPainter {
  CalibrationSilhouettePainter({
    required this.silhouettes,
    required this.view,
    required this.isPassing,
    required this.progress,
  });

  final CalibrationSilhouettes silhouettes;
  final String? view;
  final bool isPassing;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final silhouette = silhouettes[view];
    if (silhouette == null || silhouette.points.isEmpty) return;

    // Fit the body height into the box, leaving a little room top and bottom.
    final bodyHeight = size.height * 0.92;
    final origin = Offset(size.width / 2, size.height * 0.04);

    final path = Path();
    for (var i = 0; i < silhouette.points.length; i++) {
      final point = silhouette.points[i];
      // Preview is mirrored, so the guide mirrors with it.
      final dx = -(point.dx - 0.5) * bodyHeight;
      final offset = Offset(origin.dx + dx, origin.dy + point.dy * bodyHeight);
      i == 0 ? path.moveTo(offset.dx, offset.dy) : path.lineTo(offset.dx, offset.dy);
    }
    path.close();

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..color = isPassing
          ? const Color(0xFF9BE15D)
          : Colors.white.withValues(alpha: 0.55);
    canvas.drawPath(path, base);

    if (progress > 0) {
      // Hold feedback: a translucent fill rising from the feet.
      final filled = Rect.fromLTWH(
        0,
        origin.dy + bodyHeight * (1 - progress),
        size.width,
        bodyHeight * progress + origin.dy,
      );
      canvas.save();
      canvas.clipRect(filled);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF9BE15D).withValues(alpha: 0.22),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CalibrationSilhouettePainter oldDelegate) =>
      oldDelegate.view != view ||
      oldDelegate.isPassing != isPassing ||
      oldDelegate.progress != progress;
}
