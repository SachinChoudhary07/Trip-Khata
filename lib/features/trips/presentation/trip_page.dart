import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/categories.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/trip_cover.dart';
import '../../../db/app_database.dart';
import '../data/trip_repository.dart';
import 'home_page.dart' show dateRange;
import 'trip_detail_cubit.dart';

class TripPage extends StatelessWidget {
  const TripPage({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripDetailCubit(c.read<TripRepository>(), tripId),
        child: const _TripView(),
      );
}

class _TripView extends StatelessWidget {
  const _TripView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripDetailCubit, TripDetailState>(builder: (context, s) {
      if (s.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final trip = s.trip;
      if (trip == null) return const Scaffold(body: Center(child: Text('Trip not found')));
      final owe = s.myBalance < 0;
      return Scaffold(
        floatingActionButton: _Fabs(tripId: trip.id),
        body: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Stack(children: [
              TripCover(kind: trip.cover, height: 170),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    _RoundButton(icon: Icons.arrow_back, onTap: () => context.pop()),
                    const Spacer(),
                    _RoundButton(icon: Icons.ios_share, onTap: () {}),
                  ]),
                ),
              ),
            ]),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(trip.name,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                        const SizedBox(height: 2),
                        Text(dateRange(trip.startDate, trip.endDate),
                            style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ]),
                    ),
                    AvatarStack(people: [for (final m in s.members) (m.name, m.colorIndex)], max: 5),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _StatBox(label: 'Total', value: s.total)),
                    const SizedBox(width: 8),
                    Expanded(child: _StatBox(label: 'Per person', value: s.perPerson)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatBox(
                        label: owe ? 'You owe' : 'You get',
                        value: s.myBalance.abs(),
                        fg: owe ? AppColors.owe : AppColors.primary,
                        bg: owe ? AppColors.oweSoft : AppColors.primaryTint,
                        onTap: () => context.push('/trip/${trip.id}/balances'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _Tab(label: 'Expenses', active: true, onTap: () {}),
                    _Tab(label: 'Balances', onTap: () => context.push('/trip/${trip.id}/balances')),
                    _Tab(label: 'Route', onTap: () => _soon(context)),
                    _Tab(label: 'Summary', onTap: () => _soon(context)),
                  ]),
                ]),
              ),
            ),
          ),
          if (s.expenses.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('No expenses yet. Tap “Add expense” to log the first one.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            ..._expenseSlivers(context, s),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ]),
      );
    });
  }

  void _soon(BuildContext context) => ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Coming in the next build')));

  List<Widget> _expenseSlivers(BuildContext context, TripDetailState s) {
    final byDay = <DateTime, List<Expense>>{};
    for (final e in s.expenses) {
      final day = DateTime(e.spentAt.year, e.spentAt.month, e.spentAt.day);
      (byDay[day] ??= []).add(e);
    }
    final today = DateTime.now();
    String label(DateTime d) {
      final diff = DateTime(today.year, today.month, today.day).difference(d).inDays;
      final f = DateFormat('d MMM').format(d);
      if (diff == 0) return 'Today, $f';
      if (diff == 1) return 'Yesterday, $f';
      return DateFormat('EEE, d MMM').format(d);
    }

    var index = 0;
    return [
      for (final entry in byDay.entries) ...[
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Row(children: [
                Text(label(entry.key),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                const Spacer(),
                Text(formatPaise(entry.value.fold(0, (a, e) => a + e.amount)),
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -20),
            child: Container(
              color: Colors.white,
              child: Column(children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const Divider(indent: 74),
                  FadeSlideIn(
                    delay: Duration(milliseconds: 60 * (index < 10 ? index++ : 10)),
                    child: _ExpenseRow(expense: entry.value[i], state: s),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ],
    ];
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense, required this.state});
  final Expense expense;
  final TripDetailState state;

  @override
  Widget build(BuildContext context) {
    final cat = ExpenseCategory.fromName(expense.category);
    final payer = state.member(expense.paidBy);
    final payerName = payer == null ? 'Someone' : (payer.isMe ? 'You' : payer.name);
    final shares = state.sharesByExpense[expense.id] ?? const [];
    final everyone = shares.length == state.members.length;
    final who = everyone
        ? '${shares.length} people'
        : 'only ${shares.map((sh) => state.member(sh.memberId)).whereType<Member>().map((m) => m.isMe ? 'you' : m.name).join(', ')}';
    final mine = state.isMine(expense);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        CategoryTile(category: cat),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(expense.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (expense.byVoice) ...[
                const SizedBox(width: 6),
                const Icon(Icons.mic_none, size: 14, color: AppColors.textMuted),
              ],
            ]),
            const SizedBox(height: 2),
            Text('$payerName paid · $who',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(formatPaise(expense.amount),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: mine ? AppColors.text : AppColors.textMuted)),
          if (!mine)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
              child: const Text('Not in your share',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            )
          else if (!everyone)
            Text('yours ${formatPaise(state.myShare(expense))}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
      ]),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, this.fg = AppColors.text, this.bg = AppColors.background, this.onTap});
  final String label;
  final int value;
  final Color fg;
  final Color bg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: fg == AppColors.text ? AppColors.textMuted : fg)),
              CountUpText(
                value: value,
                format: formatPaise,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg),
              ),
            ]),
          ),
        ),
      );
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, this.active = false, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: active ? AppColors.primary : Colors.transparent, width: 3)),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? AppColors.primary : AppColors.textMuted,
                )),
          ),
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: const Color(0x2915181C),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 22)),
        ),
      );
}

class _Fabs extends StatelessWidget {
  const _Fabs({required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.small(
          heroTag: 'type',
          onPressed: () => context.push('/trip/$tripId/add'),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.text,
          tooltip: 'Type an expense',
          child: const Icon(Icons.edit_outlined),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'add',
          onPressed: () => context.push('/trip/$tripId/add'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: const _PulsingMic(),
          label: const Text('Add expense', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]);
}

class _PulsingMic extends StatefulWidget {
  const _PulsingMic();

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        height: 30,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Stack(alignment: Alignment.center, children: [
            Transform.scale(
              scale: 1 + _c.value * 0.6,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.45 * (1 - _c.value)),
                ),
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.add, size: 18, color: AppColors.primary),
            ),
          ]),
        ),
      );
}
