import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/trip_cover.dart';
import '../cloud/cloud_sync.dart';
import '../trips/data/trip_repository.dart';

/// v1 is fully offline, so both buttons lead to profile setup on this phone.
/// Google sign-in (free on Firebase Spark) is wired in with cloud backup in v2.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

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
                    const Text('Set up on this phone in a few seconds. No account needed to start.',
                        style: TextStyle(fontSize: 15, color: AppColors.textMuted, height: 1.5)),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () async {
                        final cloud = context.read<CloudSync>();
                        final repo = context.read<TripRepository>();
                        final messenger = ScaffoldMessenger.of(context);
                        if (!cloud.available) {
                          messenger.showSnackBar(const SnackBar(
                            content: Text('Cloud sign-in isn’t set up in this build. Setting you up offline.'),
                          ));
                          context.go('/profile/setup');
                          return;
                        }
                        try {
                          final u = await cloud.signInWithGoogle();
                          if (await repo.getProfile() == null && (u.displayName ?? '').isNotEmpty) {
                            await repo.saveProfile(name: u.displayName!);
                          }
                          if (context.mounted) context.go('/profile/setup');
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
                        }
                      },
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      icon: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Text('G',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.phone_android, size: 18),
                      label: const Text('Use phone number'),
                    ),
                    const SizedBox(height: 8),
                    const Text('Phone login needs paid SMS, so it comes in a later version.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => context.go('/profile/setup'),
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
