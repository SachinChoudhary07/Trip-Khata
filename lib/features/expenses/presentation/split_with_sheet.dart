import 'package:flutter/material.dart';

import '../../../core/categories.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../db/app_database.dart';
import '../domain/split_calculator.dart';

/// What the "Split with" sheet returns.
class SplitChoice {
  const SplitChoice({
    required this.mode,
    required this.selected,
    this.amounts = const {},
    this.weights = const {},
  });

  final SplitMode mode;
  final Set<String> selected;

  /// By amount: memberId -> paise.
  final Map<String, int> amounts;

  /// By shares: memberId -> weight (e.g. rooms).
  final Map<String, int> weights;

  /// Final shares in paise for [amount]. Null when "by amount" doesn't add up.
  Map<String, int>? sharesFor(int amount, List<String> order, String payerId) {
    final ids = order.where(selected.contains).toList();
    if (ids.isEmpty) return null;
    switch (mode) {
      case SplitMode.equally:
        return SplitCalculator.equally(amount, ids, payerId: payerId);
      case SplitMode.byAmount:
        final parts = {for (final id in ids) id: amounts[id] ?? 0};
        return SplitCalculator.isValidByAmount(amount, parts) ? parts : null;
      case SplitMode.byShares:
        final w = {for (final id in ids) id: weights[id] ?? 1};
        final r = SplitCalculator.byShares(amount, w, payerId: payerId);
        return r.isEmpty ? null : r;
    }
  }

  String get modeName => switch (mode) {
        SplitMode.equally => 'equally',
        SplitMode.byAmount => 'byAmount',
        SplitMode.byShares => 'byShares',
      };
}

Future<SplitChoice?> showSplitWithSheet(
  BuildContext context, {
  required List<Member> members,
  required SplitChoice current,
  required int amount,
  required String title,
  required Member payer,
  required ExpenseCategory category,
}) =>
    showModalBottomSheet<SplitChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _SplitWithSheet(
          members: members,
          initial: current,
          amount: amount,
          title: title,
          payer: payer,
          category: category,
        ),
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
  final SplitChoice initial;
  final int amount;
  final String title;
  final Member payer;
  final ExpenseCategory category;

  @override
  State<_SplitWithSheet> createState() => _SplitWithSheetState();
}

class _SplitWithSheetState extends State<_SplitWithSheet> {
  late SplitMode _mode = widget.initial.mode;
  late final Set<String> _on = {...widget.initial.selected};
  late final Map<String, int> _weights = {...widget.initial.weights};
  late final Map<String, TextEditingController> _amountCtl = {
    for (final m in widget.members)
      m.id: TextEditingController(
        text: (widget.initial.amounts[m.id] ?? 0) == 0 ? '' : _rupees(widget.initial.amounts[m.id]!),
      ),
  };

  static String _rupees(int paise) =>
      paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2);

  static int _paise(String text) {
    final v = double.tryParse(text.replaceAll(',', '').trim());
    return v == null ? 0 : (v * 100).round();
  }

  @override
  void dispose() {
    for (final c in _amountCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  SplitChoice get _choice => SplitChoice(
        mode: _mode,
        selected: _on,
        amounts: {for (final e in _amountCtl.entries) e.key: _paise(e.value.text)},
        weights: _weights,
      );

  @override
  Widget build(BuildContext context) {
    final order = widget.members.map((m) => m.id).toList();
    final shares = _choice.sharesFor(widget.amount, order, widget.payer.id) ?? const <String, int>{};
    final n = _on.length;
    final left = widget.members.length - n;

    String summary;
    var ok = n > 0;
    if (n == 0) {
      summary = 'Pick at least one person';
    } else if (_mode == SplitMode.byAmount) {
      final entered = _on.fold<int>(0, (a, id) => a + _paise(_amountCtl[id]!.text));
      final diff = widget.amount - entered;
      ok = diff == 0;
      summary = diff == 0
          ? 'Adds up to ${formatPaise(widget.amount)}'
          : diff > 0
              ? '${formatPaise(diff)} left to assign'
              : '${formatPaise(-diff)} too much';
    } else if (_mode == SplitMode.byShares) {
      final total = _on.fold<int>(0, (a, id) => a + (_weights[id] ?? 1));
      summary = '$total shares · ${formatPaise(total == 0 ? 0 : widget.amount ~/ total)} per share';
    } else {
      summary = '$n ${n == 1 ? 'person' : 'people'} · ${formatPaise(widget.amount ~/ n)} each'
          '${left > 0 ? ' · $left not included' : ''}';
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CategoryTile(category: widget.category, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Split with', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(
                    '${widget.title} · ${formatPaise(widget.amount)} · paid by ${widget.payer.isMe ? 'you' : widget.payer.name}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<SplitMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: SplitMode.equally, label: Text('Equally')),
                  ButtonSegment(value: SplitMode.byAmount, label: Text('By amount')),
                  ButtonSegment(value: SplitMode.byShares, label: Text('By shares')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text(
                switch (_mode) {
                  SplitMode.equally => 'Who was part of it?',
                  SplitMode.byAmount => 'How much is each person’s part?',
                  SplitMode.byShares => 'How many shares each? (e.g. rooms)',
                },
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _on.addAll(widget.members.map((m) => m.id))),
                child: const Text('Everyone'),
              ),
              TextButton(onPressed: () => setState(_on.clear), child: const Text('Clear')),
            ]),
            for (final m in widget.members) _row(m, shares[m.id] ?? 0),
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: ok ? AppColors.primaryTint : AppColors.oweSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(ok ? Icons.group_outlined : Icons.error_outline, size: 18, color: ok ? AppColors.primaryDark : AppColors.owe),
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
                onPressed: ok ? () => Navigator.pop(context, _choice) : null,
                child: const Text('Done'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(Member m, int share) {
    final on = _on.contains(m.id);
    void toggle() => setState(() => on ? _on.remove(m.id) : _on.add(m.id));
    Widget trailing;
    if (!on) {
      trailing = Text(formatPaise(0), style: const TextStyle(fontSize: 15, color: AppColors.textMuted));
    } else if (_mode == SplitMode.byAmount) {
      trailing = SizedBox(
        width: 110,
        child: TextField(
          controller: _amountCtl[m.id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            isDense: true,
            prefixText: '₹ ',
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
      );
    } else if (_mode == SplitMode.byShares) {
      final w = _weights[m.id] ?? 1;
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: w > 1 ? () => setState(() => _weights[m.id] = w - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(width: 22, child: Text('$w', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _weights[m.id] = w + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
        SizedBox(
          width: 70,
          child: Text(formatPaise(share),
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ]);
    } else {
      trailing = Text(formatPaise(share), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700));
    }

    return InkWell(
      onTap: toggle,
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
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: on ? 1 : 0.45,
            child: MemberAvatar(name: m.name, colorIndex: m.colorIndex, size: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(m.isMe ? 'You' : m.name,
                style: TextStyle(fontSize: 15, color: on ? AppColors.text : AppColors.textMuted)),
          ),
          trailing,
        ]),
      ),
    );
  }
}
