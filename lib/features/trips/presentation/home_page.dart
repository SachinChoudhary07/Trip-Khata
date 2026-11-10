import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/trip_cover.dart';
import '../../../db/app_database.dart';
import '../data/trip_repository.dart';
import 'active_trip_sheet.dart';
import 'trips_cubit.dart';

String dateRange(DateTime? s, DateTime? e) {
  if (s == null) return 'No dates';
  final d = DateFormat('d MMM');
  if (e == null) return d.format(s);
  if (s.month == e.month && s.year == e.year) return '${s.day}–${d.format(e)}';
  return '${d.format(s)} – ${d.format(e)}';
}

/// Home tab body. The bottom bar and the TripsCubit come from MainShell.
class HomeBody extends StatelessWidget {
  const HomeBody({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: BlocBuilder<TripsCubit, TripsState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());
          return CustomScrollView(slivers: [
            const SliverToBoxAdapter(child: _Header()),
            if (state.trips.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: _EmptyHome())
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: Row(children: [
                    Text(state.active != null ? 'Active trip' : 'No active trip',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                    const Spacer(),
                    const Icon(Icons.offline_pin_outlined, size: 15, color: AppColors.primary),
                    const SizedBox(width: 4),
                    const Text('Saved on this phone', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: FadeSlideIn(
                  child: state.active != null ? TripCard(summary: state.active!) : const _NoActiveTrip(),
                ),
              ),
              if (state.past.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
                    child: Text('Other trips',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                  ),
                ),
                SliverList.separated(
                  itemCount: state.past.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => FadeSlideIn(
                    delay: Duration(milliseconds: 120 + 70 * (i < 6 ? i : 6)),
                    child: _TripRow(summary: state.past[i]),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ]);
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Profile?>(
      stream: context.read<TripRepository>().watchProfile(),
      builder: (context, snap) {
        final p = snap.data;
        final first = p?.name.trim().split(RegExp(r'\s+')).first;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(first == null || first.isEmpty ? 'Hello' : 'Hello, $first',
                    style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
                const SizedBox(height: 2),
                const Text('Your trips', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ]),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/brand/logo.png', width: 40, height: 40),
            ),
          ]),
        );
      },
    );
  }
}

/// Home card for a trip: cover, title, dates, three stats, budget, actions.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.summary});
  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = summary.trip;
    final bal = summary.myBalance;
    final perPerson = summary.members.isEmpty ? 0 : summary.total ~/ summary.members.length;
    final dayText = summary.isOngoing && t.startDate != null && t.endDate != null
        ? 'Day ${DateTime.now().difference(t.startDate!).inDays + 1} of ${t.endDate!.difference(t.startDate!).inDays + 1}'
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0F15181C), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x1415181C), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/trip/${t.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Cover with status and people
            SizedBox(
              height: 136,
              child: Stack(children: [
                Positioned.fill(child: TripCover(kind: t.cover, height: 136)),
                Positioned(
                  left: 14,
                  top: 14,
                  child: _Pill(
                    dot: dayText != null,
                    text: dayText ?? (summary.isOngoing ? 'Ongoing' : dateRange(t.startDate, t.endDate)),
                  ),
                ),
                Positioned(
                  right: 14,
                  top: 12,
                  child: AvatarStack(people: [for (final m in summary.members) (m.name, m.colorIndex)], size: 30, max: 4),
                ),
              ]),
            ),
            // Title block
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                    const SizedBox(height: 4),
                    _MetaRow(items: [
                      (Icons.calendar_today_outlined, dateRange(t.startDate, t.endDate)),
                      (Icons.group_outlined, '${summary.members.length} people'),
                    ]),
                  ]),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right, color: AppColors.textMuted),
                ),
              ]),
            ),
            // Stats
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                child: IntrinsicHeight(
                  child: Row(children: [
                    _Stat(label: 'Total', value: summary.total),
                    const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
                    _Stat(label: 'Per person', value: perPerson),
                    const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
                    _Stat(
                      label: bal < 0 ? 'You owe' : (bal > 0 ? 'You get' : 'You'),
                      value: bal.abs(),
                      color: bal < 0 ? AppColors.owe : (bal > 0 ? AppColors.primary : AppColors.text),
                      settled: bal == 0,
                    ),
                  ]),
                ),
              ),
            ),
            // Budget
            if (t.budget != null && t.budget! > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(children: [
                  Row(children: [
                    const Text('Budget', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    const Spacer(),
                    Text('${formatPaise(summary.total)} of ${formatPaise(t.budget!)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: (summary.total / t.budget!).clamp(0.0, 1.0).toDouble()),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => LinearProgressIndicator(
                        value: v,
                        minHeight: 8,
                        backgroundColor: AppColors.lineSoft,
                        color: summary.total > t.budget! ? AppColors.owe : AppColors.primary,
                      ),
                    ),
                  ),
                ]),
              ),
            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push('/trip/${t.id}/voice'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.mic, size: 18),
                    label: const Text('Speak to add'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/trip/${t.id}/add'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Type'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.items});
  final List<(IconData, String)> items;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 14, runSpacing: 4, children: [
        for (final i in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i.$1, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 5),
            Text(i.$2, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ]),
      ]);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color = AppColors.text, this.settled = false});
  final String label;
  final int value;
  final Color color;
  final bool settled;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: settled
                  ? const Text('Settled', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))
                  : CountUpText(
                      value: value,
                      format: formatPaise,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color),
                    ),
            ),
          ]),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.dot = false});
  final String text;
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF2F9E5B), shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.summary});
  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = summary.trip;
    final b = summary.myBalance;
    final status = b == 0 ? 'Settled' : (b < 0 ? 'You owe ${formatPaise(-b)}' : 'You get ${formatPaise(b)}');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/trip/${t.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 56, height: 56, child: TripCover(kind: t.cover, height: 56, animate: false)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('${dateRange(t.startDate, t.endDate)} · ${summary.members.length} people',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatPaise(summary.total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: b < 0 ? AppColors.owe : (b > 0 ? AppColors.primary : AppColors.textMuted),
                    )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shown when trips exist but none is active (e.g. the active one was deleted).
class _NoActiveTrip extends StatelessWidget {
  const _NoActiveTrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Which trip are you on?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text('Pick one to add expenses to it from anywhere, even the home screen widget.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.35)),
            ]),
          ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => pickActiveTrip(context),
            child: const Text('Choose'),
          ),
        ]),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.add_road, 'Create a trip'),
      (Icons.group_add_outlined, 'Add friends'),
      (Icons.mic_none, 'Log & split'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeSlideIn(
          child: Image.asset('assets/brand/empty_trips.png', height: 220, fit: BoxFit.contain),
        ),
        const SizedBox(height: 20),
        const FadeSlideIn(
          delay: Duration(milliseconds: 100),
          child: Text('Plan your first trip',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        ),
        const SizedBox(height: 8),
        const FadeSlideIn(
          delay: Duration(milliseconds: 160),
          child: Text(
            'Track who paid what on the road, even without network. Settle up in a few taps at the end.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 24),
        FadeSlideIn(
          delay: const Duration(milliseconds: 220),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: Column(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(12)),
                      child: Icon(steps[i].$1, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text('${i + 1}. ${steps[i].$2}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
                if (i < steps.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 22),
                    child: Icon(Icons.chevron_right, size: 18, color: AppColors.border),
                  ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 24),
        FadeSlideIn(
          delay: const Duration(milliseconds: 280),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/trip/new'),
              icon: const Icon(Icons.add),
              label: const Text('Start a trip'),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => context.push('/join'),
          icon: const Icon(Icons.group_add_outlined, size: 18),
          label: const Text('Join a friend’s trip'),
        ),
      ]),
    );
  }
}
