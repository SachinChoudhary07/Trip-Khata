import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../trips/data/trip_repository.dart';
import 'cloud_sync.dart';

void _toast(BuildContext context, String m) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

String _friendly(Object e) {
  final s = e.toString();
  if (e is SyncException) return e.message;
  if (s.contains('canceled') || s.contains('cancelled')) return 'Sign-in was cancelled.';
  if (s.contains('network')) return 'No internet. Try again when you have signal.';
  return 'Something went wrong: $s';
}

/// Share a trip so friends can add expenses from their own phones.
Future<void> showShareTripSheet(BuildContext context, String tripId, String tripName) async {
  final cloud = context.read<CloudSync>();
  if (!cloud.available) {
    _toast(context, 'Cloud sync isn’t set up in this build yet. The trip stays on this phone.');
    return;
  }
  String? code;
  try {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    code = await cloud.shareTrip(tripId);
  } catch (e) {
    if (context.mounted) _toast(context, _friendly(e));
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (code == null || !context.mounted) return;
  final message = 'Join my trip “$tripName” on TripKhata so we can split expenses together.\n'
      'Open TripKhata → + → Join a trip, and enter code: $code';
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Trip shared', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Friends join with this code and add expenses from their phones. Everything syncs when there’s signal.',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.45)),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code!));
              _toast(context, 'Code copied');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primarySoft, width: 2),
              ),
              child: Column(children: [
                Text(code!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 8, color: AppColors.primaryDark)),
                const SizedBox(height: 4),
                const Text('Tap to copy', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Share.share(message),
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('Send to the group'),
          ),
        ]),
      ),
    ),
  );
}

/// Join someone else's trip with a 6-character code.
class JoinTripPage extends StatefulWidget {
  const JoinTripPage({super.key});

  @override
  State<JoinTripPage> createState() => _JoinTripPageState();
}

class _JoinTripPageState extends State<JoinTripPage> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final cloud = context.read<CloudSync>();
    final repo = context.read<TripRepository>();
    setState(() => _busy = true);
    try {
      final tripId = await cloud.joinTrip(_code.text);
      if (!mounted) return;
      final members = await repo.getMembers(tripId);
      final uid = cloud.user!.uid;
      if (!members.any((m) => m.uid == uid) && mounted) {
        final pick = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          builder: (c) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text('Which one is you?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('So your balance shows as “You”.', style: TextStyle(color: AppColors.textMuted)),
              ),
              for (final m in members.where((m) => m.uid == null))
                ListTile(
                  leading: MemberAvatar(name: m.name, colorIndex: m.colorIndex, size: 36),
                  title: Text(m.name),
                  onTap: () => Navigator.pop(c, m.id),
                ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: AppColors.primaryTint, child: Icon(Icons.add, color: AppColors.primaryDark)),
                title: const Text('I’m not on the list'),
                onTap: () => Navigator.pop(c, '+new'),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        );
        if (pick == '+new') {
          final profile = await repo.getProfile();
          await repo.addMeToTrip(tripId, profile?.name ?? cloud.user?.displayName ?? 'Me', uid, upiId: profile?.upiId);
        } else if (pick != null) {
          await repo.claimMember(tripId, pick, uid);
        }
      }
      if (mounted) context.pushReplacement('/trip/$tripId');
    } catch (e) {
      if (mounted) _toast(context, _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    final ok = _code.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length == 6;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
        title: const Text('Join a trip'),
      ),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Enter the code your friend shared', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('You’ll see the trip’s expenses and can add your own. It keeps working offline.',
            style: TextStyle(fontSize: 15, color: AppColors.textMuted, height: 1.45)),
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          maxLength: 7,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 8),
          decoration: const InputDecoration(hintText: 'ABC123', counterText: ''),
        ),
        const SizedBox(height: 20),
        if (!cloud.available)
          const Text('Cloud sync isn’t set up in this build yet.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.owe))
        else
          FilledButton(
            onPressed: ok && !_busy ? _join : null,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(cloud.user == null ? 'Sign in with Google and join' : 'Join trip'),
          ),
      ]),
    );
  }
}

/// Account card for the Profile tab.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    final u = cloud.user;
    Widget body;
    if (!cloud.available) {
      body = const ListTile(
        leading: Icon(Icons.cloud_off_outlined, color: AppColors.textMuted),
        title: Text('Cloud sync'),
        subtitle: Text('Not set up in this build. Everything is saved on this phone.'),
      );
    } else if (u == null) {
      body = ListTile(
        leading: const Icon(Icons.cloud_outlined, color: AppColors.primary),
        title: const Text('Sign in with Google'),
        subtitle: const Text('Share trips with friends and back them up'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          try {
            await cloud.signInWithGoogle();
          } catch (e) {
            if (context.mounted) _toast(context, _friendly(e));
          }
        },
      );
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.cloud_done_outlined, color: AppColors.primary),
          title: Text(u.email ?? u.displayName ?? 'Signed in'),
          subtitle: const Text('Shared trips sync automatically'),
          trailing: TextButton(onPressed: cloud.signOut, child: const Text('Sign out')),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.person_remove_outlined, color: AppColors.owe),
          title: const Text('Delete account', style: TextStyle(color: AppColors.owe)),
          subtitle: const Text('Leave all shared trips and delete your sign-in'),
          onTap: () => _deleteAccount(context, cloud),
        ),
      ]);
    }
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}

Future<void> _deleteAccount(BuildContext context, CloudSync cloud) async {
  var eraseLocal = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'You will leave every shared trip and they will be removed from this phone. '
            'Friends keep those trips and the expenses in them. Your push tokens and Google sign-in '
            'are deleted from TripKhata. This can’t be undone.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: eraseLocal,
            onChanged: (v) => set(() => eraseLocal = v ?? false),
            title: const Text('Also erase all trips and my profile from this phone'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.owe, minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final router = GoRouter.of(context);
  try {
    await cloud.deleteAccount(eraseLocal: eraseLocal);
    if (eraseLocal) {
      router.go('/onboarding');
    } else if (context.mounted) {
      _toast(context, 'Account deleted');
    }
  } catch (e) {
    if (context.mounted) _toast(context, _friendly(e));
  }
}
