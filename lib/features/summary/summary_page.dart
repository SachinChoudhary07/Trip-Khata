import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/categories.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/trip_cover.dart';
import '../trips/data/trip_repository.dart';
import '../trips/presentation/home_page.dart' show dateRange;
import '../trips/presentation/trip_detail_cubit.dart';
import 'summary_pdf.dart';

class SummaryPage extends StatelessWidget {
  const SummaryPage({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripDetailCubit(c.read<TripRepository>(), tripId),
        child: BlocBuilder<TripDetailCubit, TripDetailState>(builder: (context, s) {
          if (s.loading || s.trip == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final trip = s.trip!;

          // Spend by category, biggest first.
          final byCat = <ExpenseCategory, int>{};
          for (final e in s.expenses) {
            final c = ExpenseCategory.fromName(e.category);
            byCat[c] = (byCat[c] ?? 0) + e.amount;
          }
          final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

          // Who paid the most, and the costliest day.
          final paid = <String, int>{};
          final byDay = <DateTime, int>{};
          for (final e in s.expenses) {
            paid[e.paidBy] = (paid[e.paidBy] ?? 0) + e.amount;
            final d = DateTime(e.spentAt.year, e.spentAt.month, e.spentAt.day);
            byDay[d] = (byDay[d] ?? 0) + e.amount;
          }
          final top = paid.entries.isEmpty ? null : paid.entries.reduce((a, b) => a.value >= b.value ? a : b);
          final topDay = byDay.entries.isEmpty ? null : byDay.entries.reduce((a, b) => a.value >= b.value ? a : b);
          final dayNo = topDay == null || trip.startDate == null
              ? null
              : topDay.key.difference(DateTime(trip.startDate!.year, trip.startDate!.month, trip.startDate!.day)).inDays + 1;
          final days = trip.startDate != null && trip.endDate != null ? trip.endDate!.difference(trip.startDate!).inDays + 1 : byDay.length;
          final topMember = top == null ? null : s.member(top.key);

          String shareText() {
            final b = StringBuffer('${trip.name} · TripKhata summary\n')
              ..writeln('Total: ${formatPaise(s.total)} · ${s.members.length} people · ${formatPaise(s.perPerson)} each')
              ..writeln();
            for (final c in cats) {
              b.writeln('${c.key.label}: ${formatPaise(c.value)}');
            }
            if (s.transfers.isNotEmpty) {
              b
                ..writeln()
                ..writeln('To settle:');
              for (final t in s.transfers) {
                b.writeln('${s.member(t.fromId)?.name} → ${s.member(t.toId)?.name}: ${formatPaise(t.amount)}');
              }
            }
            return b.toString();
          }

          return Scaffold(
            appBar: AppBar(
              leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
              title: const Text('Trip summary'),
              actions: [
                IconButton(
                  tooltip: 'Export PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () async {
                    final bytes = await buildSummaryPdf(s);
                    final file = '${trip.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-summary.pdf';
                    await Printing.sharePdf(bytes: bytes, filename: file);
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: () => Share.share(shareText()),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share summary'),
                ),
              ),
            ),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
              FadeSlideIn(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    TripCover(kind: trip.cover, height: 120),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(trip.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                            Text('${dateRange(trip.startDate, trip.endDate)} · ${s.members.length} people',
                                style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          const Text('Total spent', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          CountUpText(
                            value: s.total,
                            format: formatPaise,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                          ),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Row(children: [
                  _Box(label: 'Per person', value: formatPaise(s.perPerson)),
                  const SizedBox(width: 8),
                  _Box(label: 'Expenses', value: '${s.expenses.length}'),
                  const SizedBox(width: 8),
                  _Box(label: 'Days', value: '$days'),
                ]),
              ),
              const SizedBox(height: 10),
              if (cats.isNotEmpty)
                FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Where the money went', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Row(children: [
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 1100),
                            curve: Curves.easeOutCubic,
                            builder: (_, t, __) => CustomPaint(
                              painter: _Donut([for (final c in cats) (c.value, c.key.fg)], t),
                              child: Center(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  const Text('Biggest', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                  Text('${cats.first.key.label} ${(cats.first.value * 100 / s.total).round()}%',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(children: [
                            for (final c in cats)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(color: c.key.fg, borderRadius: BorderRadius.circular(3)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(c.key.label, style: const TextStyle(fontSize: 13))),
                                  Text(formatPaise(c.value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                          ]),
                        ),
                      ]),
                    ]),
                  ),
                ),
              const SizedBox(height: 10),
              FadeSlideIn(
                delay: const Duration(milliseconds: 240),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: _Highlight(
                      bg: AppColors.yellowSoft,
                      label: 'Paid the most',
                      child: topMember == null
                          ? const Text('—')
                          : Row(children: [
                              MemberAvatar(name: topMember.name, colorIndex: topMember.colorIndex, size: 26),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text('${topMember.isMe ? 'You' : topMember.name} · ${formatPaise(top!.value)}',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              ),
                            ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Highlight(
                      bg: AppColors.primaryTint,
                      label: 'Costliest day',
                      child: Text(
                        topDay == null ? '—' : '${dayNo == null ? '' : 'Day $dayNo · '}${formatPaise(topDay.value)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          );
        }),
      );
}

class _Box extends StatelessWidget {
  const _Box({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.bg, required this.label, required this.child});
  final Color bg;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

class _Donut extends CustomPainter {
  _Donut(this.parts, this.t);
  final List<(int, Color)> parts;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold<int>(0, (a, p) => a + p.$1);
    if (total == 0) return;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    var start = -math.pi / 2;
    final sweepAll = 2 * math.pi * t;
    var drawn = 0.0;
    for (final p in parts) {
      final sweep = 2 * math.pi * p.$1 / total;
      final visible = math.min(sweep, sweepAll - drawn);
      if (visible <= 0) break;
      canvas.drawArc(rect, start, math.max(0.0, visible - 0.03), false, paint..color = p.$2);
      start += sweep;
      drawn += sweep;
    }
  }

  @override
  bool shouldRepaint(_Donut old) => old.t != t || old.parts != parts;
}
