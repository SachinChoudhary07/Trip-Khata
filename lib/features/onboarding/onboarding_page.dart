import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

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
    ('Settle up in a tap', 'See who owes whom with the fewest payments, then pay over UPI with the amount filled in.'),
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
                  SizedBox(height: 300, child: _Illustration(index: i, key: ValueKey(i))),
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

/// Onboarding art (assets/onboarding/ob1-3.png, sources in design/).
/// Fades in, then floats gently.
class _Illustration extends StatefulWidget {
  const _Illustration({super.key, required this.index});
  final int index;

  @override
  State<_Illustration> createState() => _IllustrationState();
}

class _IllustrationState extends State<_Illustration> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, math.sin(_c.value * 2 * math.pi) * 6),
          child: child,
        ),
        child: Image.asset(
          'assets/onboarding/ob${widget.index + 1}.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
