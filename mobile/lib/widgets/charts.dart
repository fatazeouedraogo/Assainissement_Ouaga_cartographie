import 'package:flutter/material.dart';

import '../core/theme.dart';

class BandChart extends StatelessWidget {
  const BandChart({
    super.key,
    required this.days,
    required this.mean,
    this.lo,
    this.hi,
    this.color = Pal.primaryDeep,
    this.height = 210,
  });

  final List<double> days;
  final List<double> mean;
  final List<double>? lo;
  final List<double>? hi;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _BandPainter(days, mean, lo, hi, color)),
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.days, this.mean, this.lo, this.hi, this.color);
  final List<double> days;
  final List<double> mean;
  final List<double>? lo;
  final List<double>? hi;
  final Color color;

  static const _left = 44.0;
  static const _bottom = 24.0;
  static const _top = 8.0;

  String _fmt(double v) {
    final a = v.abs();
    if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(1)} M';
    if (a >= 10000) return '${(v / 1000).toStringAsFixed(0)} k';
    if (a >= 100) return v.round().toString();
    if (a >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  void _text(Canvas c, String t, Offset at, {bool right = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: body(10, c: Pal.inkSoft)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (right) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (mean.length < 2) return;
    final all = [...mean, ...?lo, ...?hi];
    var minY = all.reduce((a, b) => a < b ? a : b);
    var maxY = all.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    final pad = (maxY - minY) * 0.06;
    minY -= pad;
    maxY += pad;
    final minX = days.first;
    final maxX = days.last == days.first ? days.first + 1 : days.last;
    final w = size.width - _left - 6;
    final h = size.height - _top - _bottom;
    Offset pt(int i, double v) => Offset(
      _left + (days[i] - minX) / (maxX - minX) * w,
      _top + (1 - (v - minY) / (maxY - minY)) * h,
    );

    final grid = Paint()
      ..color = Pal.line
      ..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final y = _top + h * g / 4;
      canvas.drawLine(Offset(_left, y), Offset(size.width - 6, y), grid);
      _text(canvas, _fmt(maxY - (maxY - minY) * g / 4), Offset(_left - 6, y), right: true);
    }
    for (final f in const [0.0, 0.5, 1.0]) {
      final d = minX + (maxX - minX) * f;
      _text(canvas, 'J${d.round()}', Offset(_left + w * f, size.height - 8), center: true);
    }

    if (lo != null && hi != null) {
      final band = Path()..moveTo(pt(0, hi![0]).dx, pt(0, hi![0]).dy);
      for (var i = 1; i < mean.length; i++) {
        band.lineTo(pt(i, hi![i]).dx, pt(i, hi![i]).dy);
      }
      for (var i = mean.length - 1; i >= 0; i--) {
        band.lineTo(pt(i, lo![i]).dx, pt(i, lo![i]).dy);
      }
      band.close();
      canvas.drawPath(band, Paint()..color = color.withValues(alpha: 0.16));
    }

    final line = Path()..moveTo(pt(0, mean[0]).dx, pt(0, mean[0]).dy);
    for (var i = 1; i < mean.length; i++) {
      line.lineTo(pt(i, mean[i]).dx, pt(i, mean[i]).dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BandPainter old) =>
      old.mean != mean || old.lo != lo || old.hi != hi || old.color != color;
}
