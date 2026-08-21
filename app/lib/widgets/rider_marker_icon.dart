import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 15-colour palette for other riders' dot markers (S9 spec: "Other riders:
/// 16px, unique colour from a 15-colour palette, initials label" —
/// docs/product/features/active-ride-mode.md). Chosen by eye for mutual
/// contrast and for legibility of white initials text on top, not derived
/// from any existing design token (this screen had no rider-colour token
/// before this change). Deliberately excludes ChaloColors.primary (orange)
/// so a party member's dot can never be confused with the "You" marker.
const List<Color> riderColorPalette = [
  Color(0xFF2E86DE), // blue
  Color(0xFF10AC84), // teal green
  Color(0xFF8854D0), // violet
  Color(0xFFD63031), // red
  Color(0xFFF5A623), // amber
  Color(0xFF00B8D9), // cyan
  Color(0xFFEC4899), // pink
  Color(0xFF6C5CE7), // indigo
  Color(0xFF20BF6B), // green
  Color(0xFFEE5A24), // burnt orange-red (still distinct from primary orange)
  Color(0xFF0984E3), // sky blue
  Color(0xFFB8860B), // dark gold (darker than amber above for contrast)
  Color(0xFFA29BFE), // lavender
  Color(0xFF00CEC9), // turquoise
  Color(0xFFE17055), // coral
];

/// Deterministic colour for a given rider, stable across rebuilds/reconnects
/// as long as the userId doesn't change — same hashing approach the old
/// `_hueFor` used, just against the new palette.
Color riderColorFor(String userId) {
  final index = userId.hashCode.abs() % riderColorPalette.length;
  return riderColorPalette[index];
}

/// Up to 2 characters, uppercase, derived from a display name — "Shaurya
/// Garwal" -> "SG", "You" -> "Y", "Rider AB12" -> "RA". Good enough for a
/// small map dot; not meant to be a robust i18n-safe initials algorithm.
String initialsFor(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
}

/// Rasterizes rider-dot marker bitmaps for use with `Marker.icon`.
///
/// New pattern for this codebase — `BitmapDescriptor.defaultMarkerWithHue`
/// can only re-tint Google Maps' stock teardrop pin, it can't render a
/// filled circle with initials and a glow ring. The standard Flutter
/// technique for a fully custom marker is to draw directly onto a
/// `ui.Canvas` via a `ui.PictureRecorder` (no widget needs to be mounted to
/// the tree for this — simpler and more reliable here than going through
/// `RenderRepaintBoundary`) and rasterize the result to PNG bytes, which
/// `BitmapDescriptor.bytes` then accepts.
class RiderMarkerIcon {
  RiderMarkerIcon._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Builds (or returns a cached) circular marker bitmap.
  ///
  /// [devicePixelRatio] should come from `MediaQuery` so the marker is
  /// rendered at the device's actual screen density — otherwise markers
  /// (which are raster images, not vector widgets, once handed to the map
  /// SDK) look soft on high-DPI screens.
  static Future<BitmapDescriptor> build({
    required String initials,
    required Color color,
    required double diameter,
    required bool glow,
    required double devicePixelRatio,
  }) async {
    final cacheKey =
        '$initials|${color.toARGB32()}|$diameter|$glow|$devicePixelRatio';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    // Extra canvas padding so the glow ring's blur isn't clipped at the
    // bitmap edge.
    final padding = glow ? diameter * 0.6 : diameter * 0.2;
    final logicalSize = diameter + padding * 2;
    final pixelSize = (logicalSize * devicePixelRatio).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, pixelSize.toDouble(), pixelSize.toDouble()),
    );
    canvas.scale(devicePixelRatio);

    final center = Offset(logicalSize / 2, logicalSize / 2);
    final radius = diameter / 2;

    if (glow) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, radius + padding * 0.5, glowPaint);
    }

    // White ring first so the dot reads clearly against both light and
    // dark map tiles, then the colour fill on top.
    canvas.drawCircle(center, radius + 2, Paint()..color = Colors.white);
    canvas.drawCircle(center, radius, Paint()..color = color);

    if (initials.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: diameter * 0.42,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelSize, pixelSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final descriptor = BitmapDescriptor.bytes(
      Uint8List.fromList(bytes),
      // Keeps the on-map logical size correct despite rendering at
      // devicePixelRatio resolution for sharpness — without this the
      // marker would appear devicePixelRatio times too large on screen.
      imagePixelRatio: devicePixelRatio,
    );
    _cache[cacheKey] = descriptor;
    return descriptor;
  }
}
