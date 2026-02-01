import 'dart:math' as math;

import 'package:flutter/material.dart';

class VinylDisc extends StatelessWidget {
  const VinylDisc({super.key, required this.cover});

  final ImageProvider cover;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final s = constraints.biggest.shortestSide;
          final label = s * 0.46;
          return DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const _DiscRim(),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: _GrooveDisc(),
                ),
                _LabelCover(cover: cover, size: label),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white10),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DiscRim extends StatelessWidget {
  const _DiscRim();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xFF182119).withOpacity(0.25),
            const Color(0xFF0A0F0B).withOpacity(0.35),
            const Color(0xFF0A0F0B).withOpacity(0.8),
          ],
          stops: const [0.7, 0.88, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, 16),
          ),
        ],
      ),
    );
  }
}

class _GrooveDisc extends StatelessWidget {
  const _GrooveDisc();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GroovePainter(),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF070A08),
        ),
      ),
    );
  }
}

class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withOpacity(0.06)
      ..strokeCap = StrokeCap.round;

    // Concentric grooves.
    const rings = 52;
    for (var i = 0; i < rings; i++) {
      final t = i / rings;
      final rr = r * (0.22 + 0.78 * t);
      base
        ..strokeWidth = (t < 0.2) ? 0.5 : 0.35
        ..color = Colors.white.withOpacity(0.02 + (1 - t) * 0.04);
      canvas.drawCircle(c, rr, base);
    }

    // Subtle highlight arc.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.08);
    final rect = Rect.fromCircle(center: c, radius: r * 0.92);
    canvas.drawArc(rect, -math.pi * 0.78, math.pi * 0.28, false, arc);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LabelCover extends StatelessWidget {
  const _LabelCover({required this.cover, required this.size});

  final ImageProvider cover;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(image: cover, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white10, width: 1.2),
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.14),
                    Colors.black.withOpacity(0.35),
                  ],
                  stops: const [0.55, 0.82, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
