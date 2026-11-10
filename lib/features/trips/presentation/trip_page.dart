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
import '../../cloud/cloud_sync.dart';
import '../../cloud/share_join.dart';
import 'contact_picker.dart';
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
      final bal = s.myBalance;
      final top = MediaQuery.of(context).padding.top;
      final places = [trip.fromPlace, trip.toPlace].where((p) => p.isNotEmpty).join(' → ');

      return Scaffold(
        backgroundColor: AppColors.background,
        floatingActionButton: _Fabs(tripId: trip.id),
        body: CustomScrollView(slivers: [
          // Collapsing cover. The trip name appears in the bar once collapsed.
          SliverAppBar(
            pinned: true,
            expandedHeight: 190,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            leadingWidth: 64,
            leading: Center(child: _RoundButton(icon: Icons.arrow_back, onTap: () => context.pop())),
            actions: [
              _RoundButton(
                icon: trip.joinCode == null ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                onTap: () => showShareTripSheet(context, trip.id, trip.name),
              ),
              const SizedBox(width: 8),
              _RoundButton(icon: Icons.person_add_alt, onTap: () => _addPeople(context, s)),
              const SizedBox(width: 8),
              _RoundButton(icon: Icons.pie_chart_outline, onTap: () => context.push('/trip/${trip.id}/summary')),
              const SizedBox(width: 8),
              _RoundButton(icon: Icons.more_vert, onTap: () => _tripMenu(context, s)),
              const SizedBox(width: 12),
            ],
            flexibleSpace: LayoutBuilder(builder: (context, box) {
              final collapsed = box.maxHeight <= kToolbarHeight + top + 12;
              return Stack(fit: StackFit.expand, children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: collapsed ? 0 : 1,
                  child: TripCover(kind: trip.cover, height: box.maxHeight),
                ),
                Positioned(
                  left: 72,
                  right: 120,
                  top: top,
                  height: kToolbarHeight,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: collapsed ? 1 : 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(trip.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]);
            }),
          ),
          // Title, meta and people
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trip.name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.2)),
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 6, children: [
                  _Meta(icon: Icons.calendar_today_outlined, text: dateRange(trip.startDate, trip.endDate)),
                  if (places.isNotEmpty && places != trip.name) _Meta(icon: Icons.route_outlined, text: places),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  AvatarStack(people: [for (final m in s.members) (m.name, m.colorIndex)], size: 32, max: 5),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${s.members.length} people',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  ),
                  TextButton.icon(
                    onPressed: () => _addPeople(context, s),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ]),
                const SizedBox(height: 14),
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _StatBox(label: 'Total', value: s.total)),
                    const SizedBox(width: 8),
                    Expanded(child: _StatBox(label: 'Per person', value: s.perPerson)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatBox(
                        label: bal < 0 ? 'You owe' : (bal > 0 ? 'You get' : 'Balance'),
                        value: bal.abs(),
                        fg: bal < 0 ? AppColors.owe : (bal > 0 ? AppColors.primary : AppColors.text),
                        bg: bal < 0 ? AppColors.oweSoft : (bal > 0 ? AppColors.primaryTint : AppColors.background),
                        trailing: true,
                        onTap: () => context.push('/trip/${trip.id}/balances'),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          // Tabs stay pinned under the bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              child: Container(
                color: Colors.white,
                child: Column(children: [
                  Expanded(
                    child: Row(children: [
                      _Tab(label: 'Expenses', active: true, onTap: () {}),
                      _Tab(label: 'Balances', onTap: () => context.push('/trip/${trip.id}/balances')),
                      _Tab(label: 'Route', onTap: () => context.push('/trip/${trip.id}/route')),
                      _Tab(label: 'Summary', onTap: () => context.push('/trip/${trip.id}/summary')),
                    ]),
                  ),
                  const Divider(height: 1),
                ]),
              ),
            ),
          ),
          if (s.expenses.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                child: Column(children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.receipt_long_outlined, color: AppColors.primary, size: 30),
                  ),
                  const SizedBox(height: 14),
                  const Text('No expenses yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Tap “Speak to add” and say something like “Rahul ne 1500 ka petrol bharwaya”.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, height: 1.45)),
                ]),
              ),
            )
          else
            ..._expenseSlivers(context, s),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ]),
      );
    });
  }

  /// Edit / delete / leave, depending on whether the trip is shared.
  Future<void> _tripMenu(BuildContext context, TripDetailState s) async {
    final trip = s.trip!;
    final cloud = context.read<CloudSync>();
    final shared = trip.joinCode != null;
    final repo = context.read<TripRepository>();
    final owner = shared ? await cloud.isOwner(trip.id) : null;
    final isActive = (await repo.getProfile())?.activeTripId == trip.id;
    if (!context.mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          isActive
              ? ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('End trip'),
                  subtitle: const Text('No trip will be active. Expenses and balances stay.'),
                  onTap: () => Navigator.pop(c, 'end'),
                )
              : ListTile(
                  leading: const Icon(Icons.play_circle_outline, color: AppColors.primary),
                  title: const Text('Make this the active trip'),
                  subtitle: const Text('Quick add, voice and the home widget will add here'),
                  onTap: () => Navigator.pop(c, 'activate'),
                ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit trip'),
            subtitle: const Text('Name, places, dates, budget, cover'),
            onTap: () => Navigator.pop(c, 'edit'),
          ),
          if (!shared)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.owe),
              title: const Text('Delete trip', style: TextStyle(color: AppColors.owe)),
              subtitle: const Text('Removes it and all its expenses from this phone'),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          if (shared)
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.owe),
              title: const Text('Leave trip', style: TextStyle(color: AppColors.owe)),
              subtitle: const Text('Stop syncing and remove it from this phone. Others keep it.'),
              onTap: () => Navigator.pop(c, 'leave'),
            ),
          if (shared && owner == true)
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: AppColors.owe),
              title: const Text('Delete for everyone', style: TextStyle(color: AppColors.owe)),
              subtitle: const Text('You created this trip. It disappears from all phones.'),
              onTap: () => Navigator.pop(c, 'deleteAll'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      context.push('/trip/${trip.id}/edit');
      return;
    }
    if (action == 'activate' || action == 'end') {
      await repo.setActiveTrip(action == 'activate' ? trip.id : null);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'activate' ? '${trip.name} is now your active trip' : 'Trip ended. No trip is active.'),
        ));
      }
      return;
    }
    final unsettled = s.transfers.isNotEmpty;
    final (title, body, button) = switch (action) {
      'delete' => (
          'Delete “${trip.name}”?',
          'All ${s.expenses.length} expenses, stops and bill photos of this trip will be deleted from this phone. This can’t be undone.',
          'Delete',
        ),
      'leave' => (
          'Leave “${trip.name}”?',
          '${unsettled ? 'Some payments are still pending. ' : ''}The trip will be removed from this phone. '
              'Everyone else keeps it, and you can join again with the code.',
          'Leave',
        ),
      _ => (
          'Delete “${trip.name}” for everyone?',
          'It will disappear from every phone in the group, with all expenses. This can’t be undone.',
          'Delete for everyone',
        ),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.owe, minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(d, true),
            child: Text(button),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final repo = context.read<TripRepository>();
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    router.go('/home');
    switch (action) {
      case 'delete':
        await repo.deleteTrip(trip.id);
      case 'leave':
        await cloud.leaveTrip(trip.id);
      default:
        await cloud.deleteForEveryone(trip.id);
    }
    messenger.showSnackBar(SnackBar(content: Text(action == 'leave' ? 'You left ${trip.name}' : '${trip.name} deleted')));
  }

  Future<void> _addPeople(BuildContext context, TripDetailState s) async {
    final repo = context.read<TripRepository>();
    final tripId = s.trip!.id;
    final already = s.members.map((m) => m.name.toLowerCase()).toSet();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.contacts_outlined),
            title: const Text('From contacts'),
            onTap: () => Navigator.pop(c, 'contacts'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Type a name'),
            onTap: () => Navigator.pop(c, 'name'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text('New people start at ₹0. Older expenses are not changed.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ]),
      ),
    );
    if (!context.mounted || choice == null) return;
    List<String>? names;
    if (choice == 'contacts') {
      names = await pickContacts(context, already: already);
    } else {
      final c = TextEditingController();
      final n = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Add a person'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Name'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Add')),
          ],
        ),
      );
      if (n != null && n.isNotEmpty) names = [n];
    }
    if (names != null && names.isNotEmpty) await repo.addMembers(tripId, names);
  }

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(children: [
              Text(label(entry.key),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
              const Spacer(),
              Text(formatPaise(entry.value.fold(0, (a, e) => a + e.amount)),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < entry.value.length; i++) ...[
                if (i > 0) const Divider(indent: 70, height: 1),
                FadeSlideIn(
                  delay: Duration(milliseconds: 60 * (index < 10 ? index++ : 10)),
                  child: _ExpenseRow(expense: entry.value[i], state: s),
                ),
              ],
            ]),
          ),
        ),
      ],
    ];
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.child});
  final Widget child;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_TabsHeader oldDelegate) => true;
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]);
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
    return InkWell(
      onTap: () => context.push('/trip/${expense.tripId}/expense/${expense.id}'),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    this.fg = AppColors.text,
    this.bg = AppColors.background,
    this.onTap,
    this.trailing = false,
  });
  final String label;
  final int value;
  final Color fg;
  final Color bg;
  final VoidCallback? onTap;
  final bool trailing;

  @override
  Widget build(BuildContext context) => Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg == AppColors.text ? AppColors.textMuted : fg)),
                ),
                if (trailing) Icon(Icons.chevron_right, size: 16, color: fg == AppColors.text ? AppColors.textMuted : fg),
              ]),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: CountUpText(
                  value: value,
                  format: formatPaise,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg),
                ),
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
          onPressed: () => context.push('/trip/$tripId/voice'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: const _PulsingMic(),
          label: const Text('Speak to add', style: TextStyle(fontWeight: FontWeight.w600)),
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
              child: const Icon(Icons.mic, size: 18, color: AppColors.primary),
            ),
          ]),
        ),
      );
}
