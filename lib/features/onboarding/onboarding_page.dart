import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/categories.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/trip_cover.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pc = PageController();
  int _i = 0;

  static const _slides = [
    ('Add expenses in seconds',
        'Type it, or just say it out loud. TripKhata fills in the amount, who paid and the category.'),
    ('Works without internet', 'Highways and hill stations rarely have signal. Everything is saved on your phone first.'),
    ('Remember the whole route', 'Every stop, hotel and dhaba on one map, with what you spent at each of them.'),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_i == _slides.length - 1) {
      context.go('/login');
    } else {
      _pc.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Skip', style: TextStyle(color: AppColors.textMuted)),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(height: 260, child: _Illustration(index: i, key: ValueKey(i))),
                  const SizedBox(height: 36),
                  FadeSlideIn(
                    key: ValueKey('t$i'),
                    delay: const Duration(milliseconds: 120),
                    child: Text(_slides[i].$1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  ),
                  const SizedBox(height: 10),
                  FadeSlideIn(
                    key: ValueKey('b$i'),
                    delay: const Duration(milliseconds: 220),
                    child: Text(_slides[i].$2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.textMuted)),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Row(children: [
              for (var i = 0; i < _slides.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _i ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: const StadiumBorder(),
                ),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right),
                label: Text(_i == _slides.length - 1 ? 'Get started' : 'Next'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    switch (index) {
      case 0:
        return Stack(children: [
          Positioned(
            left: 30,
            right: 30,
            top: 20,
            child: FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Color(0x1415181C), blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: Column(children: [
                  for (final (i, r) in const [
                    (ExpenseCategory.fuel, '₹1,500'),
                    (ExpenseCategory.food, '₹860'),
                    (ExpenseCategory.stay, '₹3,200'),
                  ].indexed)
                    FadeSlideIn(
                      delay: Duration(milliseconds: 300 + 120 * i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          CategoryTile(category: r.$1, size: 34),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(height: 8, width: 100, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4))),
                              const SizedBox(height: 6),
                              Container(height: 6, width: 70, decoration: BoxDecoration(color: AppColors.lineSoft, borderRadius: BorderRadius.circular(3))),
                            ]),
                          ),
                          Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            bottom: 24,
            child: FadeSlideIn(
              delay: Duration(milliseconds: 900),
              child: _Bubble(text: '“Rahul paid 1500 for petrol”'),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: FadeSlideIn(
              delay: const Duration(milliseconds: 700),
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.mic, color: Colors.white, size: 32),
              ),
            ),
          ),
        ]);
      case 1:
        return Stack(children: [
          Positioned.fill(
            top: 20,
            bottom: 20,
            child: ClipRRect(borderRadius: BorderRadius.circular(24), child: const TripCover(kind: 'desert', height: 220)),
          ),
          const Positioned(
            left: 16,
            top: 0,
            child: FadeSlideIn(delay: Duration(milliseconds: 300), child: _Badge(icon: Icons.cloud_off, text: 'No network', color: AppColors.owe)),
          ),
          const Positioned(
            right: 16,
            bottom: 0,
            child: FadeSlideIn(delay: Duration(milliseconds: 700), child: _Badge(icon: Icons.check_circle, text: 'Saved on phone', color: AppColors.primary)),
          ),
        ]);
      default:
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            color: const Color(0xFFE9ECE6),
            child: Stack(children: [
              const Positioned.fill(child: _RouteSketch()),
              for (final (i, p) in const [
                (Alignment(0.65, 0.75), ExpenseCategory.fuel),
                (Alignment(0.1, 0.2), ExpenseCategory.food),
                (Alignment(-0.35, -0.35), ExpenseCategory.stay),
                (Alignment(-0.7, -0.8), ExpenseCategory.tickets),
              ].indexed)
                Align(
                  alignment: p.$1,
                  child: FadeSlideIn(delay: Duration(milliseconds: 500 + 220 * i), child: CategoryTile(category: p.$2, size: 36)),
                ),
            ]),
          ),
        );
    }
  }
}

class _RouteSketch extends StatelessWidget {
  const _RouteSketch();

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1600),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(painter: _RoutePainter(t)),
      );
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, h * 0.28), Offset(w, h * 0.3), road);
    canvas.drawLine(Offset(w * 0.4, 0), Offset(w * 0.45, h), road);
    final route = Path()
      ..moveTo(w * 0.85, h * 0.9)
      ..cubicTo(w * 0.7, h * 0.7, w * 0.55, h * 0.75, w * 0.53, h * 0.6)
      ..cubicTo(w * 0.5, h * 0.4, w * 0.35, h * 0.35, w * 0.3, h * 0.3)
      ..cubicTo(w * 0.22, h * 0.22, w * 0.18, h * 0.15, w * 0.15, h * 0.1);
    final m = route.computeMetrics().first;
    canvas.drawPath(
      m.extractPath(0, m.length * t),
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.t != t;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.yellowSoft,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF4A3300))),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x1A15181C), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
}
