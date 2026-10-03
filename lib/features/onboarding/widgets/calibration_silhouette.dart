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
  const CalibrationSilhouette(this.points, this.engineTop, this.engineFeet, this.engineMidX);

  /// Normalized by body height: y from 0 (head top) to 1 (feet), x centred on 0.5.
  final List<Offset> points;

  /// Where the native engine would place this body's head top, feet and centre
  /// (it estimates them from shoulders, hips and ankles), in the same coordinates.
  final double engineTop;
  final double engineFeet;
  final double engineMidX;

  factory CalibrationSilhouette.fromJson(Map<String, dynamic> json) {
    final anchors = json['engineAnchors'] as Map<String, dynamic>;
    return CalibrationSilhouette(
      [
        for (final point in json['points'] as List)
          Offset((point[0] as num).toDouble(), (point[1] as num).toDouble()),
      ],
      (anchors['top'] as num).toDouble(),
      (anchors['feet'] as num).toDouble(),
      (anchors['midX'] as num).toDouble(),
    );
  }
}

/// The framing target the native engine checks, in normalized buffer coordinates.
class CalibrationGuide {
  const CalibrationGuide({
    this.bodyHeight = 0.62,
    this.minBodyHeight = 0.55,
    this.maxBodyHeight = 0.69,
    this.maxCentreOffset = 0.06,
    this.bufferAspect = 9 / 16,
  });

  final double bodyHeight;
  final double minBodyHeight;
  final double maxBodyHeight;
  final double maxCentreOffset;

  /// width / height of the camera buffer the preview shows (aspect-filled, mirrored).
  final double bufferAspect;

  factory CalibrationGuide.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CalibrationGuide();
    double read(String key, double fallback) => (map[key] as num?)?.toDouble() ?? fallback;
    return CalibrationGuide(
      bodyHeight: read('bodyHeight', 0.62),
      minBodyHeight: read('minBodyHeight', 0.55),
      maxBodyHeight: read('maxBodyHeight', 0.69),
      maxCentreOffset: read('maxCentreOffset', 0.06),
      bufferAspect: read('bufferAspect', 9 / 16),
    );
  }
}

/// Where the engine measured the user, in normalized, unmirrored buffer coordinates.
class CalibrationPerson {
  const CalibrationPerson({required this.midX, required this.feet, required this.bodyHeight});

  final double midX;
  final double feet;
  final double bodyHeight;

  static CalibrationPerson? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    return CalibrationPerson(
      midX: (map['midX'] as num).toDouble(),
      feet: (map['feet'] as num).toDouble(),
      bodyHeight: (map['bodyHeight'] as num).toDouble(),
    );
  }
}

/// Outline placement in buffer space: horizontal centre, feet line, and height.
@immutable
class _GuideBox {
  const _GuideBox(this.centreX, this.feet, this.height);

  final double centreX;
  final double feet;
  final double height;

  static _GuideBox lerp(_GuideBox a, _GuideBox b, double t) => _GuideBox(
        a.centreX + (b.centreX - a.centreX) * t,
        a.feet + (b.feet - a.feet) * t,
        a.height + (b.height - a.height) * t,
      );
}

class _GuideBoxTween extends Tween<_GuideBox> {
  _GuideBoxTween({super.end});

  @override
  _GuideBox lerp(double t) => _GuideBox.lerp(begin ?? end!, end ?? begin!, t);
}

/// The outline the user should fill, drawn over the full-screen camera preview.
///
/// It is the engine's framing target made visible: [CalibrationGuide.bodyHeight] tall,
/// centred, standing on the user's feet (how high a body sits in the frame depends on
/// where the phone is, not on the user). Once the user is inside the size and centre
/// tolerances the outline snaps onto them, so a green outline always matches the body.
class CalibrationGuideOverlay extends StatelessWidget {
  const CalibrationGuideOverlay({
    super.key,
    required this.silhouettes,
    required this.view,
    required this.guide,
    required this.person,
    required this.isPassing,
    required this.progress,
  });

  final CalibrationSilhouettes silhouettes;
  final String? view;
  final CalibrationGuide guide;
  final CalibrationPerson? person;
  final bool isPassing;
  final double progress;

  /// Feet line before anyone is in view.
  static const _defaultFeet = 0.88;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final fits = p != null &&
        (p.midX - 0.5).abs() <= guide.maxCentreOffset &&
        p.bodyHeight >= guide.minBodyHeight &&
        p.bodyHeight <= guide.maxBodyHeight;
    final target = fits
        ? _GuideBox(p.midX, p.feet, p.bodyHeight)
        : _GuideBox(0.5, p?.feet ?? _defaultFeet, guide.bodyHeight);
    return TweenAnimationBuilder<_GuideBox>(
      tween: _GuideBoxTween(end: target),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, box, _) => CustomPaint(
        size: Size.infinite,
        painter: CalibrationSilhouettePainter(
          silhouettes: silhouettes,
          view: view,
          bufferAspect: guide.bufferAspect,
          centreX: box.centreX,
          feet: box.feet,
          height: box.height,
          isPassing: isPassing,
          progress: progress,
        ),
      ),
    );
  }
}

/// Draws the outline for [view] at a buffer-space placement, mapped the way the
/// preview shows the camera: aspect-filled to the screen and mirrored.
///
/// [progress] fills the outline from the feet up while the user holds still,
/// so the wait is visible without a countdown number.
class CalibrationSilhouettePainter extends CustomPainter {
  CalibrationSilhouettePainter({
    required this.silhouettes,
    required this.view,
    required this.bufferAspect,
    required this.centreX,
    required this.feet,
    required this.height,
    required this.isPassing,
    required this.progress,
  });

  final CalibrationSilhouettes silhouettes;
  final String? view;
  final double bufferAspect;
  final double centreX;
  final double feet;
  final double height;
  final bool isPassing;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final silhouette = silhouettes[view];
    if (silhouette == null || silhouette.points.isEmpty) return;

    // Preview geometry (AVCaptureVideoPreviewLayer, .resizeAspectFill).
    final shownHeight = size.height > size.width / bufferAspect ? size.height : size.width / bufferAspect;
    final shownWidth = shownHeight * bufferAspect;
    final left = (size.width - shownWidth) / 2;
    final top = (size.height - shownHeight) / 2;

    // Outline units → screen pixels, lining up the engine's own head-top/feet/centre estimates.
    final unitsToBuffer = height / (silhouette.engineFeet - silhouette.engineTop);
    final pixelsPerUnit = unitsToBuffer * shownHeight;
    final headTop = feet - height;
    final anchorX = left + (1 - centreX) * shownWidth;  // mirrored, like the preview
    Offset toScreen(Offset point) => Offset(
          anchorX - (point.dx - silhouette.engineMidX) * pixelsPerUnit,
          top + (headTop + (point.dy - silhouette.engineTop) * unitsToBuffer) * shownHeight,
        );

    final path = Path();
    for (var i = 0; i < silhouette.points.length; i++) {
      final offset = toScreen(silhouette.points[i]);
      i == 0 ? path.moveTo(offset.dx, offset.dy) : path.lineTo(offset.dx, offset.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = isPassing ? const Color(0xFF9BE15D) : Colors.white.withValues(alpha: 0.55),
    );

    if (progress > 0) {
      // Hold feedback: a translucent fill rising from the feet.
      final bounds = path.getBounds();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(
          bounds.left, bounds.bottom - bounds.height * progress, bounds.right, bounds.bottom));
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
  bool shouldRepaint(covariant CalibrationSilhouettePainter old) =>
      old.view != view ||
      old.centreX != centreX ||
      old.feet != feet ||
      old.height != height ||
      old.bufferAspect != bufferAspect ||
      old.isPassing != isPassing ||
      old.progress != progress;
}
