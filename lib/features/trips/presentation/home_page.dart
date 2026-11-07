import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/trip_cover.dart';
import '../data/trip_repository.dart';
import 'trips_cubit.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripsCubit(c.read<TripRepository>()),
        child: const _HomeView(),
      );
}

String dateRange(DateTime? s, DateTime? e) {
  if (s == null) return '';
  final d = DateFormat('d MMM');
  if (e == null) return d.format(s);
  if (s.month == e.month) return '${s.day}–${d.format(e)}';
  return '${d.format(s)} – ${d.format(e)}';
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 20,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hi there', style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w400)),
          Text('Your trips', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ]),
        actions: [
          IconButton(onPressed: () => context.push('/settings'), icon: const Icon(Icons.person_outline), tooltip: 'Profile'),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/trip/new'),
        backgroundColor: AppColors.yellow,
        foregroundColor: const Color(0xFF2A1D00),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.add),
        label: const Text('New trip', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: BlocBuilder<TripsCubit, TripsState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());
          if (state.trips.isEmpty) return const _EmptyHome();
          final ongoing = state.ongoing!;
          return ListView(padding: const EdgeInsets.only(bottom: 120), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(children: [
                Text(ongoing.isOngoing ? 'Ongoing' : 'Latest',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                const Spacer(),
                const Icon(Icons.check, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                const Text('Saved on this phone', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
            FadeSlideIn(child: _OngoingCard(summary: ongoing)),
            if (state.past.isNotEmpty) ...[
              const SectionLabel('Past trips', padding: EdgeInsets.fromLTRB(20, 22, 20, 8)),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (var i = 0; i < state.past.length; i++) ...[
                    if (i > 0) const Divider(),
                    FadeSlideIn(
                      delay: Duration(milliseconds: 120 + i * 70),
                      child: _PastTripRow(summary: state.past[i]),
                    ),
                  ],
                ]),
              ),
            ],
          ]);
        },
      ),
    );
  }
}

class _OngoingCard extends StatelessWidget {
  const _OngoingCard({required this.summary});
  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = summary.trip;
    final owe = summary.myBalance < 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x0F15181C), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F15181C), blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/trip/${t.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(clipBehavior: Clip.none, children: [
            TripCover(kind: t.cover, height: 128),
            if (summary.isOngoing && t.startDate != null && t.endDate != null)
              Positioned(
                left: 12,
                top: 12,
                child: _Pill(text: 'Day ${DateTime.now().difference(t.startDate!).inDays + 1} of '
                    '${t.endDate!.difference(t.startDate!).inDays + 1}'),
              ),
            Positioned(
              right: 12,
              bottom: -14,
              child: AvatarStack(people: [for (final m in summary.members) (m.name, m.colorIndex)], size: 30),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${dateRange(t.startDate, t.endDate)} · ${summary.members.length} people',
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _Stat(label: 'Total spent', value: summary.total)),
                Expanded(
                  child: _Stat(
                    label: owe ? 'You owe' : 'You get back',
                    value: summary.myBalance.abs(),
                    color: owe ? AppColors.owe : AppColors.primary,
                  ),
                ),
              ]),
              if (t.budget != null && t.budget! > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (summary.total / t.budget!).clamp(0.0, 1.0).toDouble()),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: AppColors.lineSoft,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${formatPaise(summary.total)} of ${formatPaise(t.budget!)} budget',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push('/trip/${t.id}/add'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add expense'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                height: 46,
                child: IconButton.filledTonal(
                  onPressed: () => context.push('/trip/${t.id}/voice'),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primarySoft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.mic_none, color: AppColors.primaryDark),
                  tooltip: 'Add by voice',
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color = AppColors.text});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        CountUpText(
          value: value,
          format: formatPaise,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ]);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF2F9E5B), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _PastTripRow extends StatelessWidget {
  const _PastTripRow({required this.summary});
  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = summary.trip;
    final b = summary.myBalance;
    final status = b == 0 ? 'Settled' : (b < 0 ? 'You owe ${formatPaise(-b)}' : 'You get ${formatPaise(b)}');
    return InkWell(
      onTap: () => context.push('/trip/${t.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 52, height: 52, child: TripCover(kind: t.cover, height: 52, animate: false)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${dateRange(t.startDate, t.endDate)} · ${summary.members.length} people',
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatPaise(summary.total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(status, style: TextStyle(fontSize: 12, color: b < 0 ? AppColors.owe : AppColors.textMuted)),
          ]),
        ]),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: const TripCover(kind: 'mountain', height: 180),
          ),
          const SizedBox(height: 28),
          const Text('No trips yet', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Start a trip, add your friends and log expenses as you go. Everything stays on your phone.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.push('/trip/new'),
            icon: const Icon(Icons.add),
            label: const Text('Start a trip'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              final id = await context.read<TripsCubit>().createSample();
              if (context.mounted) context.push('/trip/$id');
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Try a sample trip'),
          ),
        ]),
      );
}
