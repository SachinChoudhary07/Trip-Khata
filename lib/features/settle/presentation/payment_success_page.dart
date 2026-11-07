import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';

/// Shown after a payment is marked as paid. Animated tick, receipt details,
/// and the next payment still pending, if any.
class PaymentSuccessPage extends StatefulWidget {
  const PaymentSuccessPage({
    super.key,
    required this.tripId,
    required this.toName,
    required this.amount,
    this.app,
    this.nextName,
    this.nextAmount,
  });

  final String tripId;
  final String toName;
  final int amount;
  final String? app;
  final String? nextName;
  final int? nextAmount;

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage> with TickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  late final Animation<double> _pop = CurvedAnimation(parent: _c, curve: const Interval(0, 0.35, curve: Curves.easeOutBack));
  late final Animation<double> _tick = CurvedAnimation(parent: _c, curve: const Interval(0.25, 0.7, curve: Curves.easeOut));
  late final Animation<double> _ripple = CurvedAnimation(parent: _c, curve: const Interval(0.2, 1, curve: Curves.easeOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: 140,
            height: 140,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Stack(alignment: Alignment.center, children: [
                Transform.scale(
                  scale: 1 + _ripple.value * 0.6,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primarySoft.withValues(alpha: 1 - _ripple.value),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: _pop.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                    child: CustomPaint(painter: _TickPainter(_tick.value)),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 28),
          FadeSlideIn(
            delay: const Duration(milliseconds: 500),
            child: Column(children: [
              Text('${formatPaise(widget.amount)} paid',
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(height: 6),
              Text(
                'to ${widget.toName}${widget.app == null ? '' : ' via ${widget.app}'}\nMarked as paid in this trip',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: AppColors.textMuted, height: 1.45),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          FadeSlideIn(
            delay: const Duration(milliseconds: 650),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Text('Date', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                const Spacer(),
                Text(DateFormat('d MMM yyyy, h:mm a').format(DateTime.now()),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          if (widget.nextName != null && widget.nextAmount != null)
            FadeSlideIn(
              delay: const Duration(milliseconds: 780),
              child: Container(
                margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(children: [
                  MemberAvatar(name: widget.nextName!, colorIndex: 2, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Still left', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      Text('Pay ${widget.nextName} ${formatPaise(widget.nextAmount!)}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  FilledButton.tonal(
                    onPressed: () => context.pop(),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                    child: const Text('Pay now'),
                  ),
                ]),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
          ),
        ]),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final s = size.width / 24;
    final path = Path()
      ..moveTo(6.5 * s, 12.5 * s)
      ..lineTo(10.5 * s, 16.5 * s)
      ..lineTo(18 * s, 8 * s);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.t != t;
}
