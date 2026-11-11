import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Layered landscape used as a trip cover. Same four styles as the design:
/// desert, mountain, beach, temple. The sun floats gently.
class TripCover extends StatefulWidget {
  const TripCover({super.key, required this.kind, this.height = 150, this.animate = true});
  final String kind;
  final double height;
  final bool animate;

  @override
  State<TripCover> createState() => _TripCoverState();
}

class _TripCoverState extends State<TripCover> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(painter: _CoverPainter(widget.kind, _c.value)),
          ),
        ),
      );
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.kind, this.t);
  final String kind;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Design is drawn on a 390 x 160 board, scaled to cover.
    final sx = size.width / 390, sy = size.height / 160;
    final s = math.max(sx, sy);
    canvas.save();
    canvas.translate((size.width - 390 * s) / 2, (size.height - 160 * s) / 2);
    canvas.scale(s);
    final p = Paint()..isAntiAlias = true;
    final bob = math.sin(t * 2 * math.pi) * 4;
    final drift = math.sin(t * 2 * math.pi) * 20;

    void fill(Color c, Path path) => canvas.drawPath(path, p..color = c);
    // Smooth hill line through (x, y) pairs, closed down to the bottom edge.
    Path curve(List<double> pts) {
      final path = Path()..moveTo(pts[0], pts[1]);
      for (var i = 2; i + 1 < pts.length; i += 2) {
        final px = pts[i - 2], py = pts[i - 1], x = pts[i], y = pts[i + 1];
        path.quadraticBezierTo(px, py, (px + x) / 2, (py + y) / 2);
      }
      return path
        ..lineTo(pts[pts.length - 2], pts[pts.length - 1])
        ..lineTo(390, 160)
        ..lineTo(0, 160)
        ..close();
    }

    void cloud(double x, double y, double w) {
      final c = Paint()..color = Colors.white.withValues(alpha: 0.75);
      canvas.drawRRect(RRect.fromLTRBR(x + drift, y, x + w + drift, y + 10, const Radius.circular(6)), c);
      canvas.drawCircle(Offset(x + w * 0.4 + drift, y), 8, c);
    }

    switch (kind) {
      case 'beach':
        canvas.drawRect(const Rect.fromLTWH(0, 0, 390, 160), p..color = const Color(0xFFD3EAF0));
        cloud(60, 34, 34);
        cloud(200, 24, 26);
        canvas.drawCircle(Offset(96, 56 + bob), 22, p..color = const Color(0xFFF7C85A));
        canvas.drawRect(const Rect.fromLTWH(0, 98, 390, 34), p..color = const Color(0xFF4FA3B8));
        fill(const Color(0xFFEFD9AA), curve([0, 128, 90, 118, 200, 132, 390, 120, 390, 120, 390, 120]));
        final trunk = Paint()
          ..color = const Color(0xFF6B5B3E)
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(Path()..moveTo(300, 140)..cubicTo(304, 118, 300, 96, 290, 78), trunk);
        final leaf = Paint()
          ..color = const Color(0xFF2F7D5B)
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        for (final d in const [(-36.0, 10.0), (34.0, 8.0), (-30.0, -14.0), (28.0, 16.0)]) {
          canvas.drawPath(Path()..moveTo(290, 78)..quadraticBezierTo(290 + d.$1 / 2, 70, 290 + d.$1, 78 + d.$2), leaf);
        }
      case 'temple':
        canvas.drawRect(const Rect.fromLTWH(0, 0, 390, 160), p..color = const Color(0xFFECE5F2));
        cloud(60, 34, 34);
        canvas.drawCircle(Offset(76, 54 + bob), 20, p..color = const Color(0xFFF2B33D));
        fill(const Color(0xFFC7B8DA), curve([0, 112, 80, 90, 160, 100, 240, 92, 350, 84, 390, 96]));
        fill(const Color(0xFF6C5A8A), Path()
          ..moveTo(226, 104)..lineTo(226, 80)..lineTo(232, 74)..lineTo(232, 66)..lineTo(238, 56)
          ..lineTo(244, 66)..lineTo(244, 74)..lineTo(250, 80)..lineTo(250, 104)..close());
        fill(const Color(0xFF9C88B8), curve([0, 130, 90, 118, 200, 128, 390, 120, 390, 120, 390, 120]));
        fill(const Color(0xFFA9C9DA), curve([0, 142, 100, 136, 220, 146, 390, 140, 390, 140, 390, 140]));
      case 'mountain':
        canvas.drawRect(const Rect.fromLTWH(0, 0, 390, 160), p..color = const Color(0xFFDDE8EE));
        cloud(60, 34, 34);
        canvas.drawCircle(Offset(310, 46 + bob), 18, p..color = const Color(0xFFF7C85A));
        fill(const Color(0xFF8FA9B8), Path()
          ..moveTo(0, 120)..lineTo(70, 56)..lineTo(120, 100)..lineTo(180, 40)..lineTo(250, 108)
          ..lineTo(310, 66)..lineTo(390, 118)..lineTo(390, 160)..lineTo(0, 160)..close());
        fill(Colors.white, Path()..moveTo(70, 56)..lineTo(58, 67)..lineTo(82, 68)..close());
        fill(Colors.white, Path()..moveTo(180, 40)..lineTo(166, 54)..lineTo(194, 54)..close());
        fill(const Color(0xFF5E7F92), Path()
          ..moveTo(0, 134)..lineTo(60, 104)..lineTo(130, 128)..lineTo(200, 96)..lineTo(280, 130)
          ..lineTo(340, 108)..lineTo(390, 128)..lineTo(390, 160)..lineTo(0, 160)..close());
      default: // desert
        canvas.drawRect(const Rect.fromLTWH(0, 0, 390, 160), p..color = const Color(0xFFF6DDBF));
        cloud(60, 34, 34);
        cloud(200, 24, 26);
        canvas.drawCircle(Offset(300, 58 + bob), 24, p..color = const Color(0xFFF2B33D));
        fill(const Color(0xFFE7B98A), curve([0, 110, 60, 88, 120, 96, 190, 84, 320, 70, 390, 86]));
        fill(const Color(0xFF8C5A3C), Path()
          ..moveTo(150, 90)..lineTo(150, 82)..lineTo(160, 82)..lineTo(160, 72)..lineTo(166, 72)..lineTo(166, 78)
          ..lineTo(174, 78)..lineTo(174, 66)..lineTo(180, 66)..lineTo(180, 78)..lineTo(188, 78)..lineTo(188, 72)
          ..lineTo(194, 72)..lineTo(194, 82)..lineTo(210, 82)..lineTo(210, 90)..close());
        fill(const Color(0xFFC98A5E), curve([0, 124, 70, 104, 150, 118, 230, 106, 340, 100, 390, 112]));
        fill(const Color(0xFF9CC7D4), curve([0, 138, 80, 130, 170, 142, 260, 134, 350, 132, 390, 136]));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverPainter old) => old.t != t || old.kind != kind;
}
