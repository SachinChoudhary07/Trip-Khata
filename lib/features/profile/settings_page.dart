import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/common.dart';
import '../../db/app_database.dart';
import '../trips/data/trip_repository.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TripRepository>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: const Text('Profile'),
      ),
      body: StreamBuilder<Profile?>(
        stream: repo.watchProfile(),
        builder: (context, snap) {
          final p = snap.data;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(children: [
                  MemberAvatar(name: p?.name ?? '?', colorIndex: p?.colorIndex ?? 0, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p?.name ?? 'Set up your profile',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(p?.upiId ?? 'No UPI ID added',
                          style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    ]),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => context.push('/profile/edit'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit profile',
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            const FadeSlideIn(delay: Duration(milliseconds: 60), child: _Stats()),
            const SectionLabel('Preferences', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
            _Group(delay: 120, children: [
              ListTile(
                leading: const Icon(Icons.language, color: AppColors.textMuted),
                title: const Text('Voice language'),
                subtitle: Text(p?.voiceLang == 'en' ? 'English (India)' : 'Hindi + English'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final v = await showModalBottomSheet<String>(
                    context: context,
                    showDragHandle: true,
                    builder: (c) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final o in const [('hi', 'Hindi + English'), ('en', 'English (India)')])
                          ListTile(
                            title: Text(o.$2),
                            trailing: (p?.voiceLang ?? 'hi') == o.$1 ? const Icon(Icons.check, color: AppColors.primary) : null,
                            onTap: () => Navigator.pop(c, o.$1),
                          ),
                      ]),
                    ),
                  );
                  if (v != null) await repo.updateSettings(voiceLang: v);
                },
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.currency_rupee, color: AppColors.textMuted),
                title: Text('Currency'),
                subtitle: Text('Indian Rupee (₹)'),
              ),
              const Divider(),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_none, color: AppColors.textMuted),
                title: const Text('Daily reminder'),
                subtitle: const Text('Nudge at 9 PM to add the day’s expenses'),
                value: p?.reminders ?? true,
                onChanged: p == null ? null : (v) => repo.updateSettings(reminders: v),
              ),
            ]),
            const SectionLabel('Data', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
            _Group(delay: 180, children: [
              const SwitchListTile(
                secondary: Icon(Icons.cloud_outlined, color: AppColors.textMuted),
                title: Text('Back up to cloud'),
                subtitle: Text('Coming in v2. Trips stay only on this phone for now.'),
                value: false,
                onChanged: null,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.download_outlined, color: AppColors.textMuted),
                title: const Text('Export all trips'),
                subtitle: const Text('CSV file, opens in Excel or Google Sheets'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final csv = await repo.exportCsv();
                  final dir = await getTemporaryDirectory();
                  final f = File('${dir.path}/tripkhata-export.csv');
                  await f.writeAsString(csv);
                  await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], text: 'TripKhata export');
                },
              ),
            ]),
            const SizedBox(height: 16),
            const Center(
              child: Text('TripKhata 0.1 · Made in Indore', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          ]);
        },
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TripRepository>();
    return StreamBuilder<List<Trip>>(
      stream: repo.watchTrips(),
      builder: (context, trips) => StreamBuilder<List<Expense>>(
        stream: repo.watchAllExpenses(),
        builder: (context, exp) {
          final t = trips.data?.length ?? 0;
          final total = (exp.data ?? const <Expense>[]).fold<int>(0, (a, e) => a + e.amount);
          final n = exp.data?.length ?? 0;
          Widget box(String v, String l) => Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ]),
                ),
              );
          return Row(children: [
            box('$t', 'Trips'),
            const SizedBox(width: 8),
            box(formatPaise(total), 'Tracked'),
            const SizedBox(width: 8),
            box('$n', 'Expenses'),
          ]);
        },
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children, required this.delay});
  final List<Widget> children;
  final int delay;

  @override
  Widget build(BuildContext context) => FadeSlideIn(
        delay: Duration(milliseconds: delay),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      );
}
