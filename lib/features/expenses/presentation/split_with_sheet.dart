import 'package:flutter/material.dart';

import '../../../core/categories.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../db/app_database.dart';
import '../domain/split_calculator.dart';

/// "Split with" sheet: tick only the people who were part of the expense.
/// People left unticked pay nothing and their balance does not change.
Future<Set<String>?> showSplitWithSheet(
  BuildContext context, {
  required List<Member> members,
  required Set<String> selected,
  required int amount,
  required String title,
  required Member payer,
  required ExpenseCategory category,
}) =>
    showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _SplitWithSheet(
        members: members,
        initial: selected,
        amount: amount,
        title: title,
        payer: payer,
        category: category,
      ),
    );

class _SplitWithSheet extends StatefulWidget {
  const _SplitWithSheet({
    required this.members,
    required this.initial,
    required this.amount,
    required this.title,
    required this.payer,
    required this.category,
  });
  final List<Member> members;
  final Set<String> initial;
  final int amount;
  final String title;
  final Member payer;
  final ExpenseCategory category;

  @override
  State<_SplitWithSheet> createState() => _SplitWithSheetState();
}

class _SplitWithSheetState extends State<_SplitWithSheet> {
  late final Set<String> _on = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final ordered = widget.members.map((m) => m.id).where(_on.contains).toList();
    final shares = SplitCalculator.equally(widget.amount, ordered, payerId: widget.payer.id);
    final n = _on.length;
    final left = widget.members.length - n;
    final summary = n == 0
        ? 'Pick at least one person'
        : '$n ${n == 1 ? 'person' : 'people'} · ${formatPaise(widget.amount ~/ n)} each'
            '${left > 0 ? ' · $left not included' : ''}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CategoryTile(category: widget.category, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Split with', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text('${widget.title} · ${formatPaise(widget.amount)} · paid by ${widget.payer.isMe ? 'you' : widget.payer.name}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Who was part of it?',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            const Spacer(),
            TextButton(onPressed: () => setState(() => _on.addAll(widget.members.map((m) => m.id))), child: const Text('Everyone')),
            TextButton(onPressed: () => setState(_on.clear), child: const Text('Clear')),
          ]),
          for (final m in widget.members)
            _PersonRow(
              member: m,
              on: _on.contains(m.id),
              share: shares[m.id] ?? 0,
              onTap: () => setState(() => _on.contains(m.id) ? _on.remove(m.id) : _on.add(m.id)),
            ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: n == 0 ? AppColors.oweSoft : AppColors.primaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.group_outlined, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 10),
              Expanded(child: Text(summary, style: const TextStyle(fontSize: 14))),
            ]),
          ),
          const SizedBox(height: 8),
          const Text(
            'People not ticked pay nothing for this and their balance does not change. '
            'They still see it in the list as “Not in your share”.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: n == 0 ? null : () => Navigator.pop(context, _on),
              child: const Text('Done'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.member, required this.on, required this.share, required this.onTap});
  final Member member;
  final bool on;
  final int share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: on ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(7),
                border: on ? null : Border.all(color: AppColors.border, width: 2),
              ),
              child: on ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: on ? 1 : 0.45,
                child: Row(children: [
                  MemberAvatar(name: member.name, colorIndex: member.colorIndex, size: 36),
                  const SizedBox(width: 12),
                  Expanded(child: Text(member.isMe ? 'You' : member.name, style: const TextStyle(fontSize: 15))),
                  Text(formatPaise(on ? share : 0),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: on ? AppColors.text : AppColors.textMuted)),
                ]),
              ),
            ),
          ]),
        ),
      );
}
