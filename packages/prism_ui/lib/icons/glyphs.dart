import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/glyph.dart';

/// The glyphs the components of this package draw themselves.
abstract final class Glyphs {
  static const arrowBack = Glyph([
    GlyphPolyline([
      GlyphVertex(5, 12),
      GlyphVertex(19, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(11.5, 5.5),
      GlyphVertex(5, 12, 0.4),
      GlyphVertex(11.5, 18.5),
    ], role: GlyphRole.line),
  ], matchTextDirection: true);

  static const chevronBack = Glyph([
    GlyphPolyline([
      GlyphVertex(15.25, 5.5),
      GlyphVertex(8.75, 12, 0.4),
      GlyphVertex(15.25, 18.5),
    ], role: GlyphRole.line),
  ], matchTextDirection: true);

  static const chevronForward = Glyph([
    GlyphPolyline([
      GlyphVertex(8.75, 5.5),
      GlyphVertex(15.25, 12, 0.4),
      GlyphVertex(8.75, 18.5),
    ], role: GlyphRole.line),
  ], matchTextDirection: true);

  static const chevronDown = Glyph([
    GlyphPolyline([
      GlyphVertex(5.5, 8.75),
      GlyphVertex(12, 15.25, 0.4),
      GlyphVertex(18.5, 8.75),
    ], role: GlyphRole.line),
  ]);

  static const picker = Glyph([
    GlyphPolyline([
      GlyphVertex(7.5, 9.5),
      GlyphVertex(12, 5, 0.4),
      GlyphVertex(16.5, 9.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(7.5, 14.5),
      GlyphVertex(12, 19, 0.4),
      GlyphVertex(16.5, 14.5),
    ], role: GlyphRole.line),
  ]);

  static const caretDown = Glyph([
    GlyphPolyline([
      GlyphVertex(5.2, 8, 1),
      GlyphVertex(18.8, 8, 1),
      GlyphVertex(12, 16, 1),
    ], closed: true),
  ]);

  static const close = Glyph([
    GlyphPolyline([
      GlyphVertex(6, 6),
      GlyphVertex(18, 18),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(18, 6),
      GlyphVertex(6, 18),
    ], role: GlyphRole.line),
  ]);

  static const clearField = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphPolyline([
      GlyphVertex(9.3, 9.3),
      GlyphVertex(14.7, 14.7),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(14.7, 9.3),
      GlyphVertex(9.3, 14.7),
    ], role: GlyphRole.detail),
  ]);

  static const check = Glyph([
    GlyphPolyline([
      GlyphVertex(4.8, 12.5),
      GlyphVertex(9.6, 17.3),
      GlyphVertex(19.4, 6.7),
    ], role: GlyphRole.line),
  ]);

  static const more = Glyph([
    GlyphCircle(12, 4.2, 1.65, role: GlyphRole.line, solid: true),
    GlyphCircle(12, 12, 1.65, role: GlyphRole.line, solid: true),
    GlyphCircle(12, 19.8, 1.65, role: GlyphRole.line, solid: true),
  ]);

  static const dragHandle = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 7),
      GlyphVertex(20, 7),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4, 12),
      GlyphVertex(20, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4, 17),
      GlyphVertex(20, 17),
    ], role: GlyphRole.line),
  ]);

  static const sort = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 7),
      GlyphVertex(20, 7),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4, 12),
      GlyphVertex(15, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4, 17),
      GlyphVertex(10, 17),
    ], role: GlyphRole.line),
  ], matchTextDirection: true);

  static const search = Glyph([
    GlyphCircle(10.3, 10.3, 6.9, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15.18, 15.18),
      GlyphVertex(20.6, 20.6),
    ], role: GlyphRole.line),
  ]);

  static const pin = Glyph([
    GlyphPolyline([
      GlyphVertex(15.42, 3.5, 1.5),
      GlyphVertex(20.5, 8.58, 1.5),
      GlyphVertex(15.73, 13.35, 1.4),
      GlyphVertex(14.94, 19.55, 1),
      GlyphVertex(4.45, 9.06, 1),
      GlyphVertex(10.65, 8.27, 1.4),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(9.7, 14.3),
      GlyphVertex(3.5, 20.5),
    ], role: GlyphRole.line),
  ]);

  static const eye = Glyph([
    GlyphPath(
      'M3.01 11.32A10.08 10.08 0 0 1 20.99 11.32A1.5 1.5 0 0 1 20.99 12.68'
      'A10.08 10.08 0 0 1 3.01 12.68A1.5 1.5 0 0 1 3.01 11.32Z',
    ),
    GlyphCircle(12, 12, 2.8, role: GlyphRole.detail),
  ]);

  static const eyeOff = Glyph([
    GlyphPath(
      'M10.95 5.86A10.08 10.08 0 0 1 20.99 11.32A1.5 1.5 0 0 1 20.99 12.68'
      'A10.08 10.08 0 0 1 19.71 14.62',
      role: GlyphRole.line,
    ),
    GlyphPath(
      'M16.92 16.92A10.08 10.08 0 0 1 3.01 12.68A1.5 1.5 0 0 1 3.01 11.32'
      'A10.08 10.08 0 0 1 7.08 7.08',
      role: GlyphRole.line,
    ),
    GlyphArc(12, 12, 2.8, math.pi * 0.25, math.pi, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4, 4),
      GlyphVertex(20, 20),
    ], role: GlyphRole.line),
  ]);

  static const copy = Glyph([
    GlyphBox(8.5, 7.5, 20.5, 21, 2.5),
    GlyphPolyline([
      GlyphVertex(4, 16.5),
      GlyphVertex(4, 3, 2.5),
      GlyphVertex(16, 3),
    ], role: GlyphRole.line),
  ]);

  static const cut = Glyph([
    GlyphCircle(7, 17.5, 3),
    GlyphCircle(17, 17.5, 3),
    GlyphPolyline([
      GlyphVertex(9.64, 13.73),
      GlyphVertex(16.8, 3.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(14.36, 13.73),
      GlyphVertex(7.2, 3.5),
    ], role: GlyphRole.line),
  ]);

  static const paste = Glyph([
    GlyphPolyline([
      GlyphVertex(4.5, 5.2, 2.5),
      GlyphVertex(8.5, 5.2),
      GlyphVertex(8.5, 2.9, 1),
      GlyphVertex(15.5, 2.9, 1),
      GlyphVertex(15.5, 5.2),
      GlyphVertex(19.5, 5.2, 2.5),
      GlyphVertex(19.5, 21, 2.5),
      GlyphVertex(4.5, 21, 2.5),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(8.5, 5.2),
      GlyphVertex(8.5, 7.3, 1),
      GlyphVertex(15.5, 7.3, 1),
      GlyphVertex(15.5, 5.2),
    ], role: GlyphRole.detail),
  ]);

  static const selectAll = Glyph([
    GlyphPolyline([
      GlyphVertex(3.5, 7),
      GlyphVertex(3.5, 3.5, 2.5),
      GlyphVertex(7, 3.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(20.5, 7),
      GlyphVertex(20.5, 3.5, 2.5),
      GlyphVertex(17, 3.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(20.5, 17),
      GlyphVertex(20.5, 20.5, 2.5),
      GlyphVertex(17, 20.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(3.5, 17),
      GlyphVertex(3.5, 20.5, 2.5),
      GlyphVertex(7, 20.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(10.6, 3.5),
      GlyphVertex(13.4, 3.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(20.5, 10.6),
      GlyphVertex(20.5, 13.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(13.4, 20.5),
      GlyphVertex(10.6, 20.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(3.5, 13.4),
      GlyphVertex(3.5, 10.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8, 12.3),
      GlyphVertex(10.8, 15.1, 0.4),
      GlyphVertex(16, 9.2),
    ], role: GlyphRole.line),
  ]);

  static Glyph sidebar(double progress) {
    final divider = lerpDouble(8.5, 11.5, progress)!;
    return Glyph([
      const GlyphBox(3, 4.5, 21, 19.5, 3.5),
      GlyphPolyline([
        GlyphVertex(divider, 4.5),
        GlyphVertex(divider, 19.5),
      ], role: GlyphRole.detail),
      for (final y in const [8.5, 11.0, 13.5])
        GlyphPolyline([
          GlyphVertex(5.5, y),
          GlyphVertex(divider - 2.5, y),
        ], role: GlyphRole.detail),
    ], matchTextDirection: true);
  }

  static Glyph backFor(TargetPlatform platform) {
    if (kIsWeb) {
      return arrowBack;
    }
    return switch (platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => chevronBack,
      _ => arrowBack,
    };
  }
}
