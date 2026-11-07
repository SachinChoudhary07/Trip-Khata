import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/categories.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../trips/data/trip_repository.dart';

/// Splash from the design: logo pops, wordmark rises, floating expense chips,
/// hills with a car driving along the road.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2600), _go);
  }

  bool _left = false;

  Future<void> _go() async {
    if (!mounted || _left) return;
    _left = true;
    final profile = await context.read<TripRepository>().getProfile();
    if (mounted) context.go(profile == null ? '/onboarding' : '/home');
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  Animation<double> _interval(double a, double b, [Curve c = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

  @override
  Widget build(BuildContext context) {
    final pop = _interval(0.0, 0.4, Curves.easeOutBack);
    final word = _interval(0.3, 0.6);
    final tag = _interval(0.4, 0.7);
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: GestureDetector(
        onTap: _go,
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _DotsPainter())),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 300,
            child: AnimatedBuilder(
              animation: _loop,
              builder: (_, __) => CustomPaint(painter: _HillsPainter(_loop.value)),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ScaleTransition(
                scale: pop,
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/brand/logo.png', width: 104, height: 104),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _Rise(
                anim: word,
                child: const Text('TripKhata',
                    style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              ),
              const SizedBox(height: 6),
              _Rise(
                anim: tag,
                child: const Text('Group trips, sorted. Even offline.',
                    style: TextStyle(color: Color(0xFFCFE3E7), fontSize: 15)),
              ),
            ]),
          ),
          ..._chips(),
        ]),
      ),
    );
  }

  List<Widget> _chips() {
    const data = [
      (0.08, 0.17, ExpenseCategory.fuel, '₹1,500', 'Petrol', 0.45),
      (0.58, 0.14, ExpenseCategory.food, '₹860', 'Dhaba', 0.55),
      (0.09, 0.58, ExpenseCategory.stay, '₹3,200', 'Hotel', 0.65),
      (0.58, 0.60, ExpenseCategory.other, 'Split', '6 ways', 0.75),
    ];
    return [
      for (final d in data)
        Positioned.fill(
          child: LayoutBuilder(builder: (context, c) {
            final appear = _interval(d.$6, math.min(1.0, d.$6 + 0.25), Curves.easeOutBack);
            return Stack(children: [
              Positioned(
                left: c.maxWidth * d.$1,
                top: c.maxHeight * d.$2,
                child: AnimatedBuilder(
                  animation: Listenable.merge([appear, _loop]),
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, math.sin((_loop.value + d.$6) * 2 * math.pi) * 5),
                    child: Transform.scale(scale: appear.value.clamp(0.0, 1.2).toDouble(), child: child),
                  ),
                  child: _Chip(category: d.$3, amount: d.$4, label: d.$5),
                ),
              ),
            ]);
          }),
        ),
    ];
  }
}

class _Rise extends StatelessWidget {
  const _Rise({required this.anim, required this.child});
  final Animation<double> anim;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: anim,
        builder: (_, c) => Opacity(
          opacity: anim.value,
          child: Transform.translate(offset: Offset(0, 16 * (1 - anim.value)), child: c),
        ),
        child: child,
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.category, required this.amount, required this.label});
  final ExpenseCategory category;
  final String amount;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 22, offset: Offset(0, 8))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CategoryTile(category: category, size: 30),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(amount, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ]),
      );
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.12);
    for (double x = 15; x < size.width; x += 30) {
      for (double y = 15; y < size.height * 0.7; y += 30) {
        canvas.drawCircle(Offset(x, y), 1.4, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HillsPainter extends CustomPainter {
  _HillsPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 390;
    canvas.save();
    canvas.scale(sx, size.height / 300);
    final p = Paint()..isAntiAlias = true;
    canvas.drawCircle(Offset(300, 70 + math.sin(t * 2 * math.pi) * 5), 26, p..color = AppColors.yellow);
    canvas.drawPath(
        Path()
          ..moveTo(0, 150)
          ..cubicTo(70, 110, 130, 140, 200, 112)
          ..cubicTo(270, 84, 320, 80, 390, 104)
          ..lineTo(390, 300)
          ..lineTo(0, 300)
          ..close(),
        p..color = const Color(0xFF127084));
    canvas.drawPath(
        Path()
          ..moveTo(0, 200)
          ..cubicTo(80, 170, 150, 196, 230, 172)
          ..cubicTo(300, 152, 340, 150, 390, 160)
          ..lineTo(390, 300)
          ..lineTo(0, 300)
          ..close(),
        p..color = const Color(0xFF0C5463));
    final road = Path()
      ..moveTo(-30, 236)
      ..cubicTo(70, 222, 110, 168, 190, 176)
      ..cubicTo(270, 184, 300, 160, 420, 96);
    canvas.drawPath(
        road,
        Paint()
          ..color = const Color(0xFF08404C)
          ..strokeWidth = 26
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    _dashed(canvas, road, Paint()
      ..color = AppColors.yellow
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);
    canvas.drawPath(
        Path()
          ..moveTo(0, 262)
          ..cubicTo(90, 248, 200, 270, 390, 236)
          ..lineTo(390, 300)
          ..lineTo(0, 300)
          ..close(),
        p..color = const Color(0xFF083B46));

    // Car driving along the road.
    final metric = road.computeMetrics().first;
    final tangent = metric.getTangentForOffset(metric.length * t);
    if (tangent != null) {
      canvas.save();
      canvas.translate(tangent.position.dx, tangent.position.dy);
      canvas.rotate(-tangent.angle);
      final body = Paint()..color = Colors.white;
      canvas.drawRRect(RRect.fromLTRBR(-13, -8, 13, 0, const Radius.circular(3)), body);
      canvas.drawRRect(RRect.fromLTRBR(-7, -12, 6, -6, const Radius.circular(2)), body);
      canvas.drawRRect(RRect.fromLTRBR(-5, -10.5, 4, -6.5, const Radius.circular(1)), Paint()..color = AppColors.primary);
      final wheel = Paint()..color = AppColors.text;
      canvas.drawCircle(const Offset(-7, 1), 3, wheel);
      canvas.drawCircle(const Offset(7, 1), 3, wheel);
      canvas.restore();
    }
    canvas.restore();
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final ui.PathMetric m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 20) {
        canvas.drawPath(m.extractPath(d, d + 10), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HillsPainter old) => old.t != t;
}
