import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/categories.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../db/app_database.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/presentation/trip_detail_cubit.dart';
import '../domain/split_calculator.dart';
import 'split_with_sheet.dart';

class AddExpensePage extends StatelessWidget {
  const AddExpensePage({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripDetailCubit(c.read<TripRepository>(), tripId),
        child: BlocBuilder<TripDetailCubit, TripDetailState>(
          buildWhen: (a, b) => a.loading != b.loading || a.members != b.members,
          builder: (context, s) => s.loading
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : _AddExpenseForm(tripId: tripId, members: s.members, tripName: s.trip?.name ?? ''),
        ),
      );
}

class _AddExpenseForm extends StatefulWidget {
  const _AddExpenseForm({required this.tripId, required this.members, required this.tripName});
  final String tripId;
  final List<Member> members;
  final String tripName;

  @override
  State<_AddExpenseForm> createState() => _AddExpenseFormState();
}

class _AddExpenseFormState extends State<_AddExpenseForm> {
  String _amount = '';
  final _title = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.fuel;
  late String _payerId = (widget.members.where((m) => m.isMe).firstOrNull ?? widget.members.first).id;
  late Set<String> _splitWith = widget.members.map((m) => m.id).toSet();
  bool _saving = false;

  int get _paise => rupeesTextToPaise(_amount);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _key(String k) {
    setState(() {
      if (k == 'del') {
        if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
      } else if ((_amount + k).length <= 7) {
        _amount = (_amount + k).replaceFirst(RegExp(r'^0+'), '');
      }
    });
  }

  Member _member(String id) => widget.members.firstWhere((m) => m.id == id);

  Future<void> _pickPayer() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Who paid?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final m in widget.members)
            ListTile(
              leading: MemberAvatar(name: m.name, colorIndex: m.colorIndex, size: 36),
              title: Text(m.isMe ? '${m.name} (you)' : m.name),
              trailing: m.id == _payerId ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () => Navigator.pop(c, m.id),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (id != null) setState(() => _payerId = id);
  }

  Future<void> _pickSplit() async {
    final result = await showSplitWithSheet(
      context,
      members: widget.members,
      selected: _splitWith,
      amount: _paise,
      title: _title.text.trim().isEmpty ? _category.label : _title.text.trim(),
      payer: _member(_payerId),
      category: _category,
    );
    if (result != null) setState(() => _splitWith = result);
  }

  Future<void> _save() async {
    if (_paise == 0) return _toast('Enter an amount');
    if (_splitWith.isEmpty) return _toast('Pick at least one person to split with');
    setState(() => _saving = true);
    final ordered = widget.members.map((m) => m.id).where(_splitWith.contains).toList();
    final shares = SplitCalculator.equally(_paise, ordered, payerId: _payerId);
    await context.read<TripRepository>().addExpense(
          tripId: widget.tripId,
          title: _title.text.trim().isEmpty ? _category.label : _title.text.trim(),
          amount: _paise,
          category: _category.name,
          paidBy: _payerId,
          shares: [for (final e in shares.entries) NewShare(e.key, e.value)],
        );
    if (mounted) context.pop();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final payer = _member(_payerId);
    final n = _splitWith.length;
    final all = n == widget.members.length;
    final each = n == 0 ? 0 : _paise ~/ n;
    final picked = widget.members.where((m) => _splitWith.contains(m.id)).toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add expense'),
          Text(widget.tripName, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w400)),
        ]),
      ),
      body: Column(children: [
        const SizedBox(height: 12),
        _AmountDisplay(text: _amount),
        Text(
          _paise == 0 ? 'Enter an amount' : '${formatPaise(each)} each · $n ${n == 1 ? 'person' : 'people'}',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'What was it for?',
              prefixIcon: const Icon(Icons.notes, size: 20),
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            children: [
              for (final c in ExpenseCategory.values.where((c) => c != ExpenseCategory.other))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: c == _category ? AppColors.primarySoft : Colors.white,
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(
                        color: c == _category ? AppColors.primary : AppColors.border,
                        width: c == _category ? 1.5 : 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(19),
                      onTap: () => setState(() => _category = c),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
                        child: Row(children: [
                          Icon(c.icon, size: 18, color: c.fg),
                          const SizedBox(width: 6),
                          Text(c.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(
              child: _PickerBox(
                leading: MemberAvatar(name: payer.name, colorIndex: payer.colorIndex, size: 30),
                label: 'Paid by',
                value: payer.isMe ? 'You' : payer.name,
                onTap: _pickPayer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PickerBox(
                leading: AvatarStack(people: [for (final m in picked) (m.name, m.colorIndex)], size: 22, max: 3),
                label: 'Split with',
                value: all ? 'All ${widget.members.length}' : (n == 0 ? 'Nobody' : '$n people'),
                onTap: _pickSplit,
              ),
            ),
          ]),
        ),
        const Spacer(),
        Container(
          color: AppColors.background,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: SafeArea(
            top: false,
            child: Column(children: [
              _Numpad(onKey: _key),
              const SizedBox(height: 10),
              FilledButton(onPressed: _saving ? null : _save, child: const Text('Save expense')),
              const SizedBox(height: 12),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _AmountDisplay extends StatefulWidget {
  const _AmountDisplay({required this.text});
  final String text;

  @override
  State<_AmountDisplay> createState() => _AmountDisplayState();
}

class _AmountDisplayState extends State<_AmountDisplay> with SingleTickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(widget.text) ?? 0;
    final shown = n == 0 ? '0' : formatPaise(n * 100).substring(1);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('₹ ', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: c),
        child: Text(shown,
            key: ValueKey(shown),
            style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, letterSpacing: -1)),
      ),
      AnimatedBuilder(
        animation: _blink,
        builder: (_, __) => Opacity(
          opacity: _blink.value < 0.5 ? 1 : 0,
          child: Container(width: 3, height: 40, margin: const EdgeInsets.only(left: 3), color: AppColors.primary),
        ),
      ),
    ]);
  }
}

class _PickerBox extends StatelessWidget {
  const _PickerBox({required this.leading, required this.label, required this.value, required this.onTap});
  final Widget leading;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ]),
        ),
      );
}

class _Numpad extends StatelessWidget {
  const _Numpad({required this.onKey});
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', 'del'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 2.4,
      children: [
        for (final k in keys)
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onKey(k),
              child: Center(
                child: k == 'del'
                    ? const Icon(Icons.backspace_outlined, size: 22)
                    : Text(k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ],
    );
  }
}
