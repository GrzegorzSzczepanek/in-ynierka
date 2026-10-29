import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/pixel_theme.dart';

/// Łuk 270° z segmentów: wypełnione do [value], cienka linia od progu do końca.
class TargetDial extends StatelessWidget {
  const TargetDial({
    super.key,
    required this.value,
    required this.threshold,
    this.active = true,
    this.child,
  });

  final double value;
  final double threshold;
  final bool active;
  final Widget? child;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _DialPainter(value.clamp(0, 1), threshold.clamp(0, 1), active),
          child: Center(child: child),
        ),
      );
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.value, this.threshold, this.active);

  final double value;
  final double threshold;
  final bool active;

  static const segments = 36;
  static const start = 135 * math.pi / 180;
  static const sweep = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2 - 8;
    const thickness = 22.0;
    final filled = (value * segments).round();
    for (var i = 0; i < segments; i++) {
      final a0 = start + sweep * i / segments;
      final a1 = start + sweep * (i + 0.72) / segments;
      final on = active && i < filled;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..isAntiAlias = false
        ..color = !active
            ? Px.soft.withValues(alpha: 0.5)
            : on
                ? Px.accent
                : Px.accentLight.withValues(alpha: 0.7);
      canvas.drawArc(Rect.fromCircle(center: c, radius: outer - thickness / 2), a0,
          a1 - a0, false, paint);
    }
    if (active) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Px.ink;
      final t0 = start + sweep * threshold;
      canvas.drawArc(Rect.fromCircle(center: c, radius: outer + 2), t0,
          start + sweep - t0, false, line);
    }
  }

  @override
  bool shouldRepaint(_DialPainter o) =>
      o.value != value || o.threshold != threshold || o.active != active;
}
