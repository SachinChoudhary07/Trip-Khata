import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../db/app_database.dart';
import '../profile/settings_page.dart';
import '../trips/data/trip_repository.dart';
import '../trips/presentation/active_trip_sheet.dart';
import '../trips/presentation/home_page.dart';
import '../trips/presentation/trips_cubit.dart';

/// Bottom bar: Home, a big Add button in the centre, Profile.
class MainShell extends StatelessWidget {
  const MainShell({super.key, this.tab = 0});
  final int tab;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripsCubit(c.read<TripRepository>()),
        child: _Shell(initialTab: tab),
      );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.initialTab});
  final int initialTab;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late int _tab = widget.initialTab;

  Future<void> _onAdd() async {
    final state = context.read<TripsCubit>().state;
    Trip? picked = state.active?.trip;
    if (picked == null && state.trips.isNotEmpty) {
      final id = await pickActiveTrip(context);
      if (!mounted || id == null) return;
      picked = state.trips.firstWhere((t) => t.trip.id == id).trip;
    }
    if (picked == null) {
      context.push('/trip/new');
      return;
    }
    final trip = picked;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add to ${trip.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Or start something new', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _AddOption(
                  icon: Icons.mic,
                  label: 'Speak',
                  sub: 'Say it in Hinglish',
                  primary: true,
                  onTap: () => Navigator.pop(c, 'voice'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AddOption(
                  icon: Icons.edit_outlined,
                  label: 'Type',
                  sub: 'Numpad entry',
                  onTap: () => Navigator.pop(c, 'type'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _AddOption(
                  icon: Icons.location_on_outlined,
                  label: 'Check in',
                  sub: 'Save this place',
                  onTap: () => Navigator.pop(c, 'checkin'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AddOption(
                  icon: Icons.add_road,
                  label: 'New trip',
                  sub: 'Start fresh',
                  onTap: () => Navigator.pop(c, 'trip'),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => Navigator.pop(c, 'join'),
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Join a friend’s trip with a code'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'voice':
        context.push('/trip/${trip.id}/voice');
      case 'type':
        context.push('/trip/${trip.id}/add');
      case 'checkin':
        context.push('/trip/${trip.id}/checkin');
      case 'trip':
        context.push('/trip/new');
      case 'join':
        context.push('/join');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: const [HomeBody(), SettingsPage(embedded: true)]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        width: 64,
        height: 64,
        child: FloatingActionButton(
          heroTag: 'shell-add',
          onPressed: _onAdd,
          elevation: 3,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          tooltip: 'Add',
          child: const Icon(Icons.add, size: 32),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 68,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 8,
        shadowColor: const Color(0x3315181C),
        notchMargin: 8,
        shape: const CircularNotchedRectangle(),
        padding: EdgeInsets.zero,
        child: Row(children: [
          Expanded(
            child: _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
              active: _tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
          ),
          const SizedBox(width: 88),
          Expanded(
            child: _NavItem(
              icon: Icons.person_outline,
              activeIcon: Icons.person_rounded,
              label: 'Profile',
              active: _tab == 1,
              onTap: () => setState(() => _tab = 1),
            ),
          ),
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 56,
            height: 30,
            decoration: BoxDecoration(
              color: active ? AppColors.primarySoft : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(active ? activeIcon : icon, size: 22, color: active ? AppColors.primaryDark : AppColors.textMuted),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.text : AppColors.textMuted,
              )),
        ]),
      );
}

class _AddOption extends StatelessWidget {
  const _AddOption({required this.icon, required this.label, required this.sub, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
        color: primary ? AppColors.primary : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary ? Colors.white.withValues(alpha: 0.18) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: primary ? Colors.white : AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: primary ? Colors.white : AppColors.text)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: primary ? const Color(0xFFCFE3E7) : AppColors.textMuted)),
                ]),
              ),
            ]),
          ),
        ),
      );
}
