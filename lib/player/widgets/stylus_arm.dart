import 'dart:math' as math;

import 'package:flutter/material.dart';

class StylusArm extends StatelessWidget {
  const StylusArm({
    super.key,
    required this.progress,
    required this.size,
  });

  final Animation<double> progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Match screenshot: pivot near top-center, arm leans down-right when playing.
    // Paused -> arm swings away (more negative). Playing -> arm rests on disc.
    final angle = Tween<double>(begin: -0.84, end: -0.18).transform(progress.value);
    final armW = size * 0.46;
    final armH = size * 0.46;

    return Transform.rotate(
      angle: angle,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: armW,
        height: armH,
        child: CustomPaint(
          painter: _StylusPainter(),
        ),
      ),
    );
  }
}

class _StylusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width * 0.58, size.height * 0.10);
    final end = Offset(size.width * 0.90, size.height * 0.82);
    final mid = Offset(size.width * 0.78, size.height * 0.42);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withOpacity(0.88)
      ..strokeWidth = math.max(2.8, size.shortestSide * 0.024);

    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withOpacity(0.72)
      ..strokeWidth = math.max(1.4, size.shortestSide * 0.012);

    // Pivot circle.
    final knob = Paint()..color = Colors.white.withOpacity(0.92);
    canvas.drawCircle(pivot, size.shortestSide * 0.06, knob);
    canvas.drawCircle(pivot, size.shortestSide * 0.03, Paint()..color = Colors.white.withOpacity(0.20));

    // Arm curve.
    final path = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
    canvas.drawPath(path, stroke);
    canvas.drawPath(path, thin);

    // Cartridge near the end.
    final cartW = size.width * 0.13;
    final cartH = size.height * 0.08;
    final cartR = RRect.fromRectAndRadius(
      Rect.fromCenter(center: end.translate(-cartW * 0.15, -cartH * 0.10), width: cartW, height: cartH),
      Radius.circular(cartH * 0.22),
    );
    canvas.drawRRect(cartR, Paint()..color = Colors.white.withOpacity(0.88));
    canvas.drawRRect(
      cartR.deflate(cartH * 0.12),
      Paint()..color = Colors.white.withOpacity(0.15),
    );
  }

  @override
  bool shouldRepaint(covariant _StylusPainter oldDelegate) => false;
}
