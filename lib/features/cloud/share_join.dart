import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../db/app_database.dart';
import '../trips/data/trip_repository.dart';
import 'cloud_sync.dart';
import 'invite_links.dart';

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
    _toast(context, 'Cloud sync isn’t available on this phone right now. The trip stays on this phone.');
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
  final members = await context.read<TripRepository>().getMembers(tripId);
  if (!context.mounted) return;
  final others = members.where((m) => !m.isMe).toList();
  final groupLink = InviteLink(code: code).toString();
  final groupMessage = 'Join my trip “$tripName” on TripKhata so we can split expenses together.\n'
      '$groupLink\n\n'
      'Or open TripKhata → + → Join a trip, and enter code: $code';
  String memberMessage(Member m) => 'Hi ${m.name}, join my trip “$tripName” on TripKhata. '
      'This link adds you as ${m.name}:\n'
      '${InviteLink(code: code!, memberId: m.id)}\n\n'
      'Don’t have the app? The link has the download.';
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Trip shared', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Send each friend their own link. One tap and they’re in the trip as themselves. Everything syncs when there’s signal.',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.45)),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final m in others)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    MemberAvatar(name: m.name, colorIndex: m.colorIndex, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    if (m.uid != null)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_circle, size: 18, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text('Joined', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                        ]),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => Share.share(memberMessage(m)),
                        icon: const Icon(Icons.send_outlined, size: 16),
                        label: const Text('Invite'),
                      ),
                  ]),
                ),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code!));
                _toast(context, 'Code copied');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primarySoft, width: 2),
                ),
                child: Column(children: [
                  Text(code!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 8, color: AppColors.primaryDark)),
                  const SizedBox(height: 2),
                  const Text('Trip code · tap to copy', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Share.share(groupMessage),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Send one link to the group'),
            ),
          ]),
        ),
      ),
    ),
  );
}

/// Join someone else's trip with a 6-character code.
class JoinTripPage extends StatefulWidget {
  const JoinTripPage({super.key, this.code, this.memberId});

  /// Filled in from an invite link.
  final String? code;

  /// From a per-member invite link: join as this member without asking.
  final String? memberId;

  @override
  State<JoinTripPage> createState() => _JoinTripPageState();
}

class _JoinTripPageState extends State<JoinTripPage> {
  late final _code = TextEditingController(text: widget.code ?? '');
  bool _busy = false;

  bool get _codeOk => _code.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length == 6;

  @override
  void initState() {
    super.initState();
    // Opened from an invite link and already signed in: join right away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.code == null || !_codeOk) return;
      final cloud = context.read<CloudSync>();
      if (cloud.available && cloud.user != null) _join();
    });
  }

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
        final invited = widget.memberId == null ? null : members.where((m) => m.id == widget.memberId).firstOrNull;
        // A per-member link joins you as that member, unless someone already
        // took it (a forwarded link): then you pick, like with a plain code.
        if (invited != null && invited.uid == null) {
          await repo.claimMember(tripId, invited.id, uid);
          if (mounted) context.pushReplacement('/trip/$tripId');
          return;
        }
        if (invited != null && mounted) _toast(context, '${invited.name} already joined from another phone. Pick who you are.');
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
    final ok = _codeOk;
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
          autofocus: widget.code == null,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          maxLength: 7,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 8),
          decoration: const InputDecoration(hintText: 'ABC123', counterText: ''),
        ),
        const SizedBox(height: 20),
        if (!cloud.available)
          const Text('Cloud sync isn’t available on this phone right now.',
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

void _showBusy(BuildContext context, String label) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// Account card for the Profile tab.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  Future<void> _signIn(BuildContext context, CloudSync cloud) async {
    final nav = Navigator.of(context, rootNavigator: true);
    _showBusy(context, 'Signing in…');
    try {
      await cloud.signInWithGoogle();
      nav.pop();
    } catch (e) {
      nav.pop();
      final s = e.toString().toLowerCase();
      if (s.contains('cancel') || !context.mounted) return;
      _toast(context, _friendly(e));
    }
  }

  Future<void> _signOut(BuildContext context, CloudSync cloud) async {
    final router = GoRouter.of(context);
    final nav = Navigator.of(context, rootNavigator: true);
    _showBusy(context, 'Signing out…');
    try {
      await cloud.signOut();
      nav.pop();
      router.go('/login');
    } catch (e) {
      nav.pop();
      if (context.mounted) _toast(context, _friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    final u = cloud.user;
    Widget body;
    if (!cloud.available) {
      body = const ListTile(
        leading: Icon(Icons.cloud_off_outlined, color: AppColors.textMuted),
        title: Text('Cloud sync'),
        subtitle: Text('Not available on this phone right now. Everything is saved here.'),
      );
    } else if (u == null) {
      body = ListTile(
        leading: const Icon(Icons.cloud_outlined, color: AppColors.primary),
        title: const Text('Sign in with Google'),
        subtitle: const Text('Share trips with friends and back them up'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _signIn(context, cloud),
      );
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.cloud_done_outlined, color: AppColors.primary),
          title: Text(u.email ?? u.displayName ?? 'Signed in'),
          subtitle: const Text('Shared trips sync automatically'),
          trailing: TextButton(onPressed: () => _signOut(context, cloud), child: const Text('Sign out')),
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
  final nav = Navigator.of(context, rootNavigator: true);
  _showBusy(context, 'Deleting account…');
  try {
    await cloud.deleteAccount(eraseLocal: eraseLocal);
    nav.pop();
    router.go('/login');
  } catch (e) {
    nav.pop();
    final s = e.toString().toLowerCase();
    if (s.contains('cancel') || !context.mounted) return;
    _toast(context, _friendly(e));
  }
}
