import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

/// Pick people from the phone's contacts. Returns their display names.
/// Only names are read; nothing leaves the phone.
Future<List<String>?> pickContacts(BuildContext context, {Set<String> already = const {}}) async {
  final ok = await FlutterContacts.requestPermission(readonly: true);
  if (!context.mounted) return null;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contacts permission denied. You can still add people by name.')),
    );
    return null;
  }
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _ContactSheet(already: already),
  );
}

class _ContactSheet extends StatefulWidget {
  const _ContactSheet({required this.already});
  final Set<String> already;

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  List<Contact>? _all;
  String _q = '';
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    FlutterContacts.getContacts(withProperties: true, sorted: true).then((c) {
      if (mounted) setState(() => _all = c.where((x) => x.displayName.trim().isNotEmpty).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = (_all ?? const <Contact>[])
        .where((c) => _q.isEmpty || c.displayName.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            const Expanded(child: Text('Add from contacts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            Text('${_picked.length} selected', style: const TextStyle(color: AppColors.textMuted)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Search contacts',
              prefixIcon: const Icon(Icons.search, size: 20),
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _all == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final name = c.displayName.trim();
                    final added = widget.already.contains(name.toLowerCase());
                    final on = _picked.contains(name);
                    return ListTile(
                      enabled: !added,
                      leading: MemberAvatar(name: name, colorIndex: i % 6, size: 40),
                      title: Text(name),
                      subtitle: Text(added ? 'Already in this trip' : (c.phones.isEmpty ? '' : c.phones.first.number)),
                      trailing: Checkbox(
                        value: on || added,
                        onChanged: added ? null : (v) => setState(() => v == true ? _picked.add(name) : _picked.remove(name)),
                      ),
                      onTap: added ? null : () => setState(() => on ? _picked.remove(name) : _picked.add(name)),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.toList()),
                child: Text(_picked.isEmpty ? 'Pick people' : 'Add ${_picked.length}'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
