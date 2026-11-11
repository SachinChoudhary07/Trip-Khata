import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/trip_cover.dart';
import '../data/trip_repository.dart';
import 'contact_picker.dart';

/// New trip: cover, name, places, dates, budget and people, on one screen.
class CreateTripPage extends StatefulWidget {
  const CreateTripPage({super.key, this.tripId});

  /// When set, edits this trip's details instead of creating a new trip.
  final String? tripId;

  @override
  State<CreateTripPage> createState() => _CreateTripPageState();
}

class _CreateTripPageState extends State<CreateTripPage> {
  static const _covers = [('desert', 'Desert'), ('mountain', 'Hills'), ('beach', 'Beach'), ('temple', 'Temple')];
  String _cover = 'desert';
  final _name = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _budget = TextEditingController();
  final _myName = TextEditingController(text: 'You');
  final List<String> _people = [];
  DateTimeRange? _dates;
  bool _saving = false;
  String? _myUpi;

  bool get _editing => widget.tripId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      context.read<TripRepository>().getTrip(widget.tripId!).then((t) {
        if (t == null || !mounted) return;
        setState(() {
          _name.text = t.name;
          _from.text = t.fromPlace;
          _to.text = t.toPlace;
          _cover = t.cover;
          _budget.text = t.budget == null ? '' : '${t.budget! ~/ 100}';
          if (t.startDate != null) _dates = DateTimeRange(start: t.startDate!, end: t.endDate ?? t.startDate!);
        });
      });
      return;
    }
    context.read<TripRepository>().getProfile().then((p) {
      if (p == null || !mounted) return;
      setState(() {
        _myName.text = p.name;
        _myUpi = p.upiId;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _from, _to, _budget, _myName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _dates,
    );
    if (r != null) setState(() => _dates = r);
  }

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty
        ? [_from.text.trim(), _to.text.trim()].where((s) => s.isNotEmpty).join(' → ')
        : _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the trip a name or places')));
      return;
    }
    setState(() => _saving = true);
    final budgetRupees = int.tryParse(_budget.text.replaceAll(',', '').trim());
    if (_editing) {
      await context.read<TripRepository>().updateTrip(
            widget.tripId!,
            name: name,
            fromPlace: _from.text.trim(),
            toPlace: _to.text.trim(),
            startDate: _dates?.start,
            endDate: _dates?.end,
            budget: budgetRupees == null ? null : budgetRupees * 100,
            cover: _cover,
          );
      if (mounted) context.pop();
      return;
    }
    final id = await context.read<TripRepository>().createTrip(
          name: name,
          myName: _myName.text.trim().isEmpty ? 'You' : _myName.text.trim(),
          otherNames: _people,
          fromPlace: _from.text.trim(),
          toPlace: _to.text.trim(),
          startDate: _dates?.start,
          endDate: _dates?.end,
          budget: int.tryParse(_budget.text.replaceAll(',', '')) == null
              ? null
              : int.parse(_budget.text.replaceAll(',', '')) * 100,
          cover: _cover,
          myUpiId: _myUpi,
        );
    if (mounted) context.pushReplacement('/trip/$id');
  }

  @override
  Widget build(BuildContext context) {
    final d = DateFormat('d MMM yyyy');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
        title: Text(_editing ? 'Edit trip' : 'New trip'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_editing ? 'Save changes' : 'Create trip · ${_people.length + 1} people'),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: TripCover(key: ValueKey(_cover), kind: _cover, height: 150),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final c in _covers)
            ChoiceChip(
              label: Text(c.$2),
              selected: _cover == c.$1,
              onSelected: (_) => setState(() => _cover = c.$1),
              selectedColor: AppColors.primarySoft,
              side: BorderSide(color: _cover == c.$1 ? AppColors.primarySoft : AppColors.border),
              showCheckmark: false,
            ),
        ]),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Trip name', hintText: 'Rajasthan road trip')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _from, decoration: const InputDecoration(labelText: 'From'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _to, decoration: const InputDecoration(labelText: 'To'))),
        ]),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickDates,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Dates', suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
            child: Text(_dates == null ? 'Pick start and end' : '${d.format(_dates!.start)} – ${d.format(_dates!.end)}'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _budget,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Budget (optional)', prefixText: '₹ '),
        ),
        if (_editing)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 16, 4, 0),
            child: Text('People are added from the trip screen (👤+). Old expenses keep their split.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        if (!_editing) ...[
        const SectionLabel('People', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
        TextField(controller: _myName, decoration: const InputDecoration(labelText: 'Your name')),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final names = await pickContacts(context, already: _people.map((p) => p.toLowerCase()).toSet());
              if (names != null) setState(() => _people.addAll(names.where((n) => !_people.contains(n))));
            },
            icon: const Icon(Icons.contacts_outlined, size: 18),
            label: const Text('Add from contacts'),
          ),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < _people.length; i++)
            InputChip(
              avatar: MemberAvatar(name: _people[i], colorIndex: i + 1, size: 24),
              label: Text(_people[i]),
              onDeleted: () => setState(() => _people.removeAt(i)),
            ),
        ]),
        ],
      ]),
    );
  }
}
