import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/trip_cover.dart';
import '../cloud/cloud_sync.dart';
import '../trips/data/trip_repository.dart';

/// Sign in with Google (needed to share trips), or skip and use the app
/// fully offline. Both lead to profile setup on this phone.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;

  Future<void> _google() async {
    if (_busy) return;
    final cloud = context.read<CloudSync>();
    final repo = context.read<TripRepository>();
    final messenger = ScaffoldMessenger.of(context);
    if (!cloud.available) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Google sign-in isn’t available on this phone. Setting you up offline.'),
      ));
      context.go('/profile/setup');
      return;
    }
    setState(() => _busy = true);
    try {
      final u = await cloud.signInWithGoogle();
      if (await repo.getProfile() == null && (u.displayName ?? '').isNotEmpty) {
        await repo.saveProfile(name: u.displayName!);
      }
      if (mounted) context.go('/profile/setup');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final s = e.toString().toLowerCase();
      if (s.contains('cancel')) return;
      messenger.showSnackBar(SnackBar(
        content: Text(s.contains('network')
            ? 'No internet. Try again, or skip and use offline.'
            : 'Google sign-in didn’t work. Try again, or skip and use offline.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        const TripCover(kind: 'mountain', height: 260),
        Expanded(
          child: Transform.translate(
            offset: const Offset(0, -24),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 60, end: 0),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (_, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: SafeArea(
                  top: false,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Welcome to TripKhata',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                    const SizedBox(height: 6),
                    const Text('Split trip expenses with friends. Works offline, no account needed to start.',
                        style: TextStyle(fontSize: 15, color: AppColors.textMuted, height: 1.5)),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _busy ? null : _google,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        disabledBackgroundColor: AppColors.primary,
                        disabledForegroundColor: Colors.white,
                      ),
                      icon: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Text('G',
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 15)),
                            ),
                      label: Text(_busy ? 'Signing in…' : 'Continue with Google'),
                    ),
                    const SizedBox(height: 10),
                    const Text('Sign in to share trips with friends. You can also do this later in Settings.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _busy ? null : () => context.go('/profile/setup'),
                      icon: const Icon(Icons.cloud_off, size: 18),
                      label: const Text('Skip, use offline', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
