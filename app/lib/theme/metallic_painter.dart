import 'package:flutter/material.dart';

class BrushedMetalPainter extends CustomPainter {
  final Color baseColor;

  const BrushedMetalPainter({this.baseColor = const Color(0xFF2A3038)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1;

    // Draw horizontal brushed grain lines
    for (double y = 0; y < size.height; y += 2) {
      final opacity = (y % 4 == 0) ? 0.035 : 0.012;
      paint.color = Color.fromRGBO(255, 255, 255, opacity);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Top edge highlight — light catching the machined edge
    final edgePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.18),
          Colors.white.withOpacity(0.22),
          Colors.white.withOpacity(0.18),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
    canvas.drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), edgePaint..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
