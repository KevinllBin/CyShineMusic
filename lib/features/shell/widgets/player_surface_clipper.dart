import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/platform/screen_corners.dart';

/// A cached OEM quadrant, mirrored around the four independently sized corners.
/// Only the contour morphs: the player's layout and hit testing keep one clip.
class PlayerSurfaceClipper extends CustomClipper<Path> {
  const PlayerSurfaceClipper(this.surface, this.curve, this.blend);

  final RRect surface;
  final ScreenCornerCurve? curve;
  final double blend;

  @override
  Path getClip(Size size) {
    final path = Path();
    final contour = curve;
    if (contour == null || blend == 0) return path..addRRect(surface);
    final rect = surface.outerRect;
    final radii = [
      surface.trRadiusX,
      surface.brRadiusX,
      surface.blRadiusX,
      surface.tlRadiusX,
    ];
    final extent = 1 + (contour.extent - 1) * blend;
    var scale = 1.0;
    for (var i = 0; i < 4; i++) {
      final sum = (radii[i] + radii[(i + 1) % 4]) * extent;
      final edge = i.isEven ? rect.height : rect.width;
      if (sum > 0) scale = math.min(scale, edge / sum);
    }
    for (var corner = 0; corner < 4; corner++) {
      final radius = radii[corner] * scale;
      for (var i = 0; i < contour.points.length; i++) {
        // Angle correspondence avoids bunching points during the circle-to-OEM morph.
        final offset =
            Offset.lerp(contour.circle[i], contour.points[i], blend)! * radius;
        final position = switch (corner) {
          0 => Offset(rect.right - offset.dx, rect.top + offset.dy),
          1 => Offset(rect.right - offset.dy, rect.bottom - offset.dx),
          2 => Offset(rect.left + offset.dx, rect.bottom - offset.dy),
          _ => Offset(rect.left + offset.dy, rect.top + offset.dx),
        };
        if (corner == 0 && i == 0) {
          path.moveTo(position.dx, position.dy);
        } else {
          path.lineTo(position.dx, position.dy);
        }
      }
    }
    return path..close();
  }

  @override
  bool shouldReclip(PlayerSurfaceClipper oldClipper) =>
      surface != oldClipper.surface ||
      curve != oldClipper.curve ||
      blend != oldClipper.blend;
}
