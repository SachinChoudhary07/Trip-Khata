import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../db/app_database.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/presentation/trip_detail_cubit.dart';
import '../domain/settlement_calculator.dart';

class BalancesPage extends StatelessWidget {
  const BalancesPage({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripDetailCubit(c.read<TripRepository>(), tripId),
        child: const _BalancesView(),
      );
}

class _BalancesView extends StatelessWidget {
  const _BalancesView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripDetailCubit, TripDetailState>(builder: (context, s) {
      if (s.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final me = s.me;
      final mine = s.transfers.where((t) => t.fromId == me?.id || t.toId == me?.id).toList();
      final others = s.transfers.where((t) => !mine.contains(t)).toList();
      final bal = s.myBalance;
      final maxAbs = s.balances.values.fold<int>(1, (a, v) => v.abs() > a ? v.abs() : a);
      final sorted = [...s.members]..sort((a, b) => (s.balances[b.id] ?? 0).compareTo(s.balances[a.id] ?? 0));

      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Balances'),
            Text(s.trip?.name ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w400)),
          ]),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          FadeSlideIn(child: _SummaryCard(balance: bal, payments: mine.length)),
          if (mine.isNotEmpty) ...[
            const SectionLabel('Your payments', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
            _Card(children: [
              for (var i = 0; i < mine.length; i++) ...[
                if (i > 0) const Divider(),
                FadeSlideIn(
                  delay: Duration(milliseconds: 120 + 80 * i),
                  child: _MyTransferRow(transfer: mine[i], state: s),
                ),
              ],
            ]),
          ],
          const SectionLabel('Everyone', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
          _Card(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), children: [
            for (var i = 0; i < sorted.length; i++)
              _BalanceBar(
                member: sorted[i],
                value: s.balances[sorted[i].id] ?? 0,
                maxAbs: maxAbs,
                delay: Duration(milliseconds: 200 + 70 * i),
              ),
          ]),
          if (others.isNotEmpty) ...[
            const SectionLabel('Between others', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
            _Card(children: [
              for (var i = 0; i < others.length; i++) ...[
                if (i > 0) const Divider(),
                _OtherTransferRow(transfer: others[i], state: s),
              ],
            ]),
          ],
          if (s.transfers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('All settled. Nobody owes anything.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            ),
        ]),
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.balance, required this.payments});
  final int balance;
  final int payments;

  @override
  Widget build(BuildContext context) {
    final owe = balance < 0;
    final settled = balance == 0;
    final fg = settled ? AppColors.primaryDark : (owe ? AppColors.owe : AppColors.primary);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: owe ? AppColors.oweSoft : AppColors.primaryTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(settled ? 'You are settled' : (owe ? 'You owe' : 'You get back'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            CountUpText(
              value: balance.abs(),
              format: formatPaise,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: fg),
            ),
            if (!settled)
              Text('$payments ${payments == 1 ? 'payment clears' : 'payments clear'} it',
                  style: TextStyle(fontSize: 13, color: fg)),
          ]),
        ),
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(Icons.account_balance_wallet_outlined, color: fg, size: 26),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = EdgeInsets.zero});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _MyTransferRow extends StatelessWidget {
  const _MyTransferRow({required this.transfer, required this.state});
  final Transfer transfer;
  final TripDetailState state;

  Future<void> _pay(BuildContext context, Member to) async {
    var upi = to.upiId;
    if (upi == null || upi.isEmpty) {
      upi = await _askUpi(context, to);
      if (upi == null || !context.mounted) return;
      await context.read<TripRepository>().setMemberUpi(to.id, upi);
    }
    final rupees = (transfer.amount / 100).toStringAsFixed(2);
    final uri = Uri.parse('upi://pay?pa=${Uri.encodeComponent(upi)}&pn=${Uri.encodeComponent(to.name)}'
        '&am=$rupees&cu=INR&tn=${Uri.encodeComponent('TripKhata ${state.trip?.name ?? ''}')}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No UPI app found on this phone')));
      return;
    }
    final paid = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Did the payment go through?'),
        content: Text('Mark ${formatPaise(transfer.amount)} to ${to.name} as paid.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Mark as paid')),
        ],
      ),
    );
    if (paid == true && context.mounted) await context.read<TripDetailCubit>().markPaid(transfer);
  }

  Future<String?> _askUpi(BuildContext context, Member to) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text("${to.name}'s UPI ID"),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'name@okaxis'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(d, c.text.trim().isEmpty ? null : c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final iPay = transfer.fromId == state.me?.id;
    final other = state.member(iPay ? transfer.toId : transfer.fromId)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        MemberAvatar(name: other.name, colorIndex: other.colorIndex, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(iPay ? 'Pay ${other.name} ${formatPaise(transfer.amount)}' : '${other.name} pays you ${formatPaise(transfer.amount)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (iPay && other.upiId != null)
              Text(other.upiId!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
        if (iPay)
          FilledButton(
            onPressed: () => _pay(context, other),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
            child: const Text('Pay via UPI'),
          )
        else
          OutlinedButton(
            onPressed: () => context.read<TripDetailCubit>().markPaid(transfer),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: const Text('Got it'),
          ),
      ]),
    );
  }
}

class _OtherTransferRow extends StatelessWidget {
  const _OtherTransferRow({required this.transfer, required this.state});
  final Transfer transfer;
  final TripDetailState state;

  @override
  Widget build(BuildContext context) {
    final from = state.member(transfer.fromId)!;
    final to = state.member(transfer.toId)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        AvatarStack(people: [(from.name, from.colorIndex), (to.name, to.colorIndex)], size: 26),
        const SizedBox(width: 10),
        Expanded(child: Text('${from.name} → ${to.name}', style: const TextStyle(fontSize: 14))),
        Text(formatPaise(transfer.amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        TextButton(
          onPressed: () => context.read<TripDetailCubit>().markPaid(transfer),
          child: const Text('Mark paid'),
        ),
      ]),
    );
  }
}

/// Diverging bar: owes to the left (orange), gets back to the right (blue).
class _BalanceBar extends StatelessWidget {
  const _BalanceBar({required this.member, required this.value, required this.maxAbs, required this.delay});
  final Member member;
  final int value;
  final int maxAbs;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final color = value >= 0 ? AppColors.primary : AppColors.owe;
    final frac = value.abs() / maxAbs * 0.5;
    return SizedBox(
      height: 40,
      child: Row(children: [
        SizedBox(
          width: 96,
          child: Row(children: [
            MemberAvatar(name: member.name, colorIndex: member.colorIndex, size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Text(member.isMe ? 'You' : member.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: member.isMe ? FontWeight.w700 : FontWeight.w500)),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: frac),
              duration: const Duration(milliseconds: 800) + delay,
              curve: Curves.easeOutCubic,
              builder: (_, f, __) => Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 16,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.lineSoft, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                Positioned(left: w / 2, top: 11, width: 1, height: 18, child: const ColoredBox(color: AppColors.border)),
                Positioned(
                  left: value >= 0 ? w / 2 : w / 2 - w * f,
                  top: 16,
                  width: w * f,
                  height: 8,
                  child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                ),
              ]),
            );
          }),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 76,
          child: Text(formatPaise(value, sign: true),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: value == 0 ? AppColors.textMuted : color)),
        ),
      ]),
    );
  }
}
