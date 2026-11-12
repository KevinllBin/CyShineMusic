import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../equalizer_store.dart';

class EqualizerCurve extends StatelessWidget {
  const EqualizerCurve({super.key, required this.settings});

  final EqualizerSettings settings;

  @override
  Widget build(BuildContext context) => Semantics(
    label: settings.enabled ? '均衡器频响曲线' : '均衡器已关闭，当前使用原声',
    image: true,
    child: ClipRSuperellipse(
      borderRadius: prism.AppRadius.md,
      child: ColoredBox(
        color: prism.SurfaceLevel.block.colorOf(
          prism.Theme.of(context).colorScheme,
        ),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _EqualizerCurvePainter(
              settings: settings,
              scheme: Theme.of(context).colorScheme,
            ),
            child: const SizedBox(height: 176, width: double.infinity),
          ),
        ),
      ),
    ),
  );
}

class _EqualizerCurvePainter extends CustomPainter {
  const _EqualizerCurvePainter({required this.settings, required this.scheme});

  final EqualizerSettings settings;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    // Horizontal grid lines and dB labels
    const dbLines = [12.0, 0.0, -12.0];
    for (final db in dbLines) {
      final y = _gainY(db, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      _drawText(
        canvas,
        '${db > 0 ? '+' : ''}${db.round()}dB',
        Offset(6, y - 11),
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      );
    }

    // Vertical frequency grid lines and labels
    for (final frequency in const <double>[31, 125, 500, 2000, 8000, 16000]) {
      final x = _frequencyX(frequency, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      final label = frequency >= 1000
          ? '${(frequency / 1000).round()}k'
          : '${frequency.round()}';
      _drawText(
        canvas,
        label,
        Offset(x + 3, size.height - 13),
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      );
    }

    // Baseline (0 dB)
    final zeroY = _gainY(0.0, size.height);
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = scheme.outline.withValues(alpha: 0.4)
        ..strokeWidth = 1.2,
    );

    final path = Path();
    if (!settings.enabled) {
      path
        ..moveTo(0, zeroY)
        ..lineTo(size.width, zeroY);
    } else {
      for (var index = 0; index < 320; index++) {
        final normalized = index / 319;
        final frequency =
            equalizerMinFrequencyHz *
            math.pow(
              equalizerMaxFrequencyHz / equalizerMinFrequencyHz,
              normalized,
            );
        final gain = _equalizerResponseDb(
          settings,
          frequency.toDouble(),
        ).clamp(equalizerMinGainDb, equalizerMaxGainDb);
        final point = Offset(
          normalized * size.width,
          _gainY(gain.toDouble(), size.height),
        );
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
    }

    if (settings.enabled) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.2),
            scheme.primary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);
    }

    // Response curve line
    final line = Paint()
      ..color = settings.enabled
          ? scheme.primary
          : scheme.outline.withValues(alpha: 0.5)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, line);

    // Nodes for each band
    for (final band in settings.bands) {
      final x = _frequencyX(band.frequencyHz, size.width);
      final y = _gainY(band.filter.usesGain ? band.gainDb : 0, size.height);
      if (!settings.enabled || !band.enabled) {
        canvas.drawCircle(
          Offset(x, y),
          3.5,
          Paint()
            ..color = scheme.outline.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else {
        canvas.drawCircle(
          Offset(x, y),
          6.5,
          Paint()
            ..color = scheme.primary.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          Offset(x, y),
          3.5,
          Paint()
            ..color = scheme.primary
            ..style = PaintingStyle.fill,
        );
      }
    }

    if (!settings.enabled) {
      const hint = '均衡器已旁通';
      final textPainter = TextPainter(
        text: TextSpan(
          text: hint,
          style: TextStyle(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: textPainter.width + 24,
        height: textPainter.height + 12,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        Paint()..color = scheme.surfaceContainerHigh.withValues(alpha: 0.8),
      );
      textPainter.paint(canvas, Offset(rect.left + 12, rect.top + 6));
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    Color? color,
    double fontSize = 9,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? scheme.onSurfaceVariant.withValues(alpha: 0.55),
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  double _frequencyX(double frequency, double width) {
    final normalized =
        (math.log(frequency.clamp(20, 20_000)) / math.ln10 -
            math.log(20) / math.ln10) /
        (math.log(20_000) / math.ln10 - math.log(20) / math.ln10);
    return normalized * width;
  }

  double _gainY(double gain, double height) =>
      (equalizerMaxGainDb - gain) /
      (equalizerMaxGainDb - equalizerMinGainDb) *
      height;

  @override
  bool shouldRepaint(covariant _EqualizerCurvePainter oldDelegate) {
    return oldDelegate.settings != settings || oldDelegate.scheme != scheme;
  }
}

double _equalizerResponseDb(EqualizerSettings settings, double frequency) {
  if (!settings.enabled) return 0;
  var result = settings.inputGainDb + settings.outputGainDb;
  for (final band in settings.bands) {
    if (!band.enabled) continue;
    result += _biquadResponseDb(band, frequency);
  }
  return result;
}

double _biquadResponseDb(EqualizerBandSetting band, double frequency) {
  const sampleRate = 48000.0;
  final center = band.frequencyHz.clamp(1, sampleRate / 2 - 1);
  final omega = 2 * math.pi * center / sampleRate;
  final cosOmega = math.cos(omega);
  final sinOmega = math.sin(omega);
  final q = band.q.clamp(equalizerMinQ, equalizerMaxQ);
  final amplitude = math.pow(10, band.gainDb / 40).toDouble();

  late double b0;
  late double b1;
  late double b2;
  late double a0;
  late double a1;
  late double a2;

  switch (band.filter) {
    case EqualizerFilterType.peaking:
      final alpha = sinOmega / (2 * q);
      b0 = 1 + alpha * amplitude;
      b1 = -2 * cosOmega;
      b2 = 1 - alpha * amplitude;
      a0 = 1 + alpha / amplitude;
      a1 = -2 * cosOmega;
      a2 = 1 - alpha / amplitude;
    case EqualizerFilterType.lowPass:
      final alpha = sinOmega / (2 * q);
      b0 = (1 - cosOmega) / 2;
      b1 = 1 - cosOmega;
      b2 = b0;
      a0 = 1 + alpha;
      a1 = -2 * cosOmega;
      a2 = 1 - alpha;
    case EqualizerFilterType.highPass:
      final alpha = sinOmega / (2 * q);
      b0 = (1 + cosOmega) / 2;
      b1 = -(1 + cosOmega);
      b2 = b0;
      a0 = 1 + alpha;
      a1 = -2 * cosOmega;
      a2 = 1 - alpha;
    case EqualizerFilterType.lowShelf:
    case EqualizerFilterType.highShelf:
      final slope = _shelfSlope(band.gainDb, q);
      final alpha =
          sinOmega /
          2 *
          math.sqrt((amplitude + 1 / amplitude) * (1 / slope - 1) + 2);
      final rootAAlpha = 2 * math.sqrt(amplitude) * alpha;
      if (band.filter == EqualizerFilterType.lowShelf) {
        b0 =
            amplitude *
            ((amplitude + 1) - (amplitude - 1) * cosOmega + rootAAlpha);
        b1 = 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosOmega);
        b2 =
            amplitude *
            ((amplitude + 1) - (amplitude - 1) * cosOmega - rootAAlpha);
        a0 = (amplitude + 1) + (amplitude - 1) * cosOmega + rootAAlpha;
        a1 = -2 * ((amplitude - 1) + (amplitude + 1) * cosOmega);
        a2 = (amplitude + 1) + (amplitude - 1) * cosOmega - rootAAlpha;
      } else {
        b0 =
            amplitude *
            ((amplitude + 1) + (amplitude - 1) * cosOmega + rootAAlpha);
        b1 = -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosOmega);
        b2 =
            amplitude *
            ((amplitude + 1) + (amplitude - 1) * cosOmega - rootAAlpha);
        a0 = (amplitude + 1) - (amplitude - 1) * cosOmega + rootAAlpha;
        a1 = 2 * ((amplitude - 1) - (amplitude + 1) * cosOmega);
        a2 = (amplitude + 1) - (amplitude - 1) * cosOmega - rootAAlpha;
      }
  }

  final targetOmega =
      2 * math.pi * frequency.clamp(1, sampleRate / 2 - 1) / sampleRate;
  final cos1 = math.cos(targetOmega);
  final sin1 = math.sin(targetOmega);
  final cos2 = math.cos(2 * targetOmega);
  final sin2 = math.sin(2 * targetOmega);
  final numeratorReal = b0 + b1 * cos1 + b2 * cos2;
  final numeratorImag = -b1 * sin1 - b2 * sin2;
  final denominatorReal = a0 + a1 * cos1 + a2 * cos2;
  final denominatorImag = -a1 * sin1 - a2 * sin2;
  final numerator =
      numeratorReal * numeratorReal + numeratorImag * numeratorImag;
  final denominator =
      denominatorReal * denominatorReal + denominatorImag * denominatorImag;
  final power = math.max(numerator / denominator, 1e-12);
  return 10 * math.log(power) / math.ln10;
}

double _shelfSlope(double gainDb, double q) {
  final amplitude = math.pow(10, gainDb / 40).toDouble();
  final slope = 1 / (((1 / (q * q) - 2) / (1 / amplitude + amplitude)) + 1);
  return math.max(slope, 0.1);
}
