import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/categories.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../db/app_database.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/presentation/trip_detail_cubit.dart';

class ExpenseDetailPage extends StatelessWidget {
  const ExpenseDetailPage({super.key, required this.tripId, required this.expenseId});
  final String tripId;
  final String expenseId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripDetailCubit(c.read<TripRepository>(), tripId),
        child: BlocBuilder<TripDetailCubit, TripDetailState>(builder: (context, s) {
          if (s.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final e = s.expenses.where((x) => x.id == expenseId).firstOrNull;
          if (e == null) {
            return Scaffold(appBar: AppBar(), body: const Center(child: Text('This expense was deleted')));
          }
          final cat = ExpenseCategory.fromName(e.category);
          final payer = s.member(e.paidBy);
          final shares = <ExpenseShare>[...(s.sharesByExpense[e.id] ?? const <ExpenseShare>[])]
            ..sort((a, b) => (s.member(a.memberId)?.name ?? '').compareTo(s.member(b.memberId)?.name ?? ''));
          final everyone = shares.length == s.members.length;
          final notIn = s.members.where((m) => !shares.any((sh) => sh.memberId == m.id)).toList();

          Future<void> delete() async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Delete this expense?'),
                content: Text('${e.title} · ${formatPaise(e.amount)}. Balances will update for everyone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.owe, minimumSize: const Size(0, 44)),
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              await context.read<TripRepository>().deleteExpense(e.id);
              if (context.mounted) context.pop();
            }
          }

          return Scaffold(
            appBar: AppBar(
              leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
              title: const Text('Expense'),
              actions: [
                IconButton(
                  onPressed: delete,
                  icon: const Icon(Icons.delete_outline, color: AppColors.owe),
                  tooltip: 'Delete',
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 22, 16, 32), children: [
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutBack,
                  builder: (_, v, child) => Transform.scale(scale: v, child: child),
                  child: CategoryTile(category: cat, size: 64),
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Column(children: [
                  Text(e.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  CountUpText(
                    value: e.amount,
                    format: formatPaise,
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1),
                  ),
                  Text.rich(
                    TextSpan(style: const TextStyle(fontSize: 14, color: AppColors.textMuted), children: [
                      const TextSpan(text: 'Paid by '),
                      TextSpan(
                        text: payer == null ? 'someone' : (payer.isMe ? 'you' : payer.name),
                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ' · ${DateFormat('d MMM, h:mm a').format(e.spentAt)}'),
                    ]),
                  ),
                  if (e.byVoice) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.lineSoft, borderRadius: BorderRadius.circular(14)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.mic_none, size: 14, color: AppColors.textMuted),
                        SizedBox(width: 6),
                        Text('Added by voice',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      ]),
                    ),
                  ],
                ]),
              ),
              SectionLabel(
                everyone ? 'Split equally · ${shares.length} people' : 'Split between ${shares.length} of ${s.members.length}',
                padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(children: [
                  for (var i = 0; i < shares.length; i++) ...[
                    if (i > 0) const Divider(),
                    FadeSlideIn(
                      delay: Duration(milliseconds: 150 + 50 * i),
                      child: Builder(builder: (_) {
                        final sh = shares[i];
                        final m = s.member(sh.memberId);
                        final isPayer = sh.memberId == e.paidBy;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(children: [
                            MemberAvatar(name: m?.name ?? '?', colorIndex: m?.colorIndex ?? 0),
                            const SizedBox(width: 12),
                            Expanded(child: Text(m == null ? '?' : (m.isMe ? 'You' : m.name), style: const TextStyle(fontSize: 15))),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(formatPaise(sh.share), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              if (isPayer)
                                Text('paid ${formatPaise(e.amount)} · gets ${formatPaise(e.amount - sh.share)}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                            ]),
                          ]),
                        );
                      }),
                    ),
                  ],
                ]),
              ),
              if (notIn.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text(
                    'Not in this split: ${notIn.map((m) => m.isMe ? 'you' : m.name).join(', ')}. '
                    'Their balance is not affected.',
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
                  ),
                ),
            ]),
          );
        }),
      );
}
