import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Circular progress with an optional centred label. Animates value changes.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 48, this.stroke = 5, this.color, this.label});

  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, stroke, color ?? p.primary, p.surfaceMuted),
          child: label == null
              ? null
              : Center(child: Text(label!, style: context.text.labelLarge?.copyWith(fontSize: size * 0.24, fontWeight: FontWeight.w700))),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke, this.color, this.track);
  final double v, stroke;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final c = size.center(Offset.zero);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, base..color = track);
    if (v > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track;
}
