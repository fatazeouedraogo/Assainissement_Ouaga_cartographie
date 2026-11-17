import 'package:flutter/material.dart';
import 'theme.dart';

class MotifBand extends StatelessWidget {
  const MotifBand({super.key, this.height = 14});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _MotifPainter()),
      );
}

class _MotifPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = Pal.ink);
    final tri = Paint()..color = Pal.signal;
    final bone = Paint()..color = Pal.surface;
    final step = h * 1.6;
    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final p = Path();
      if (i.isEven) {
        p
          ..moveTo(x, h)
          ..lineTo(x + step / 2, h * 0.12)
          ..lineTo(x + step, h);
        canvas.drawPath(p..close(), tri);
      } else {
        p
          ..moveTo(x, 0)
          ..lineTo(x + step / 2, h * 0.88)
          ..lineTo(x + step, 0);
        canvas.drawPath(p..close(), bone);
      }
      x += step;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MoundGlyph extends StatelessWidget {
  const MoundGlyph({super.key, required this.level, required this.color, this.size = 44, this.ring = false});
  final int level;
  final Color color;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MoundPainter(level, color, ring)),
      );
}

class _MoundPainter extends CustomPainter {
  _MoundPainter(this.level, this.color, this.ring);
  final int level;
  final Color color;
  final bool ring;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final base = s.height * 0.86;
    final heights = [0.30, 0.52, 0.78];
    final spread = [0.50, 0.70, 0.92];
    final hh = s.height * heights[level.clamp(0, 2)];
    final half = w * spread[level.clamp(0, 2)] / 2;
    final path = Path()
      ..moveTo(w / 2 - half, base)
      ..quadraticBezierTo(w / 2 - half * 0.5, base - hh * 1.1, w / 2 - half * 0.1, base - hh)
      ..quadraticBezierTo(w / 2 + half * 0.2, base - hh * 1.25, w / 2 + half * 0.55, base - hh * 0.55)
      ..quadraticBezierTo(w / 2 + half * 0.9, base - hh * 0.3, w / 2 + half, base)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(path, Paint()
      ..color = Pal.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
    canvas.drawLine(Offset(w * 0.08, base), Offset(w * 0.92, base), Paint()
      ..color = Pal.ink
      ..strokeWidth = 2);
    if (ring) {
      canvas.drawCircle(Offset(w / 2, s.height / 2), s.width * 0.48, Paint()
        ..color = Pal.signal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4);
    }
  }

  @override
  bool shouldRepaint(covariant _MoundPainter old) => old.level != level || old.color != color || old.ring != ring;
}
