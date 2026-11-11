import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/cloud/share_join.dart';
import '../../features/expenses/presentation/add_expense_page.dart';
import '../../features/onboarding/login_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/profile/profile_setup_page.dart';
import '../../features/profile/settings_page.dart';
import '../../features/summary/summary_page.dart';
import '../../features/expenses/presentation/expense_detail_page.dart';
import '../../features/settle/presentation/balances_page.dart';
import '../../features/settle/presentation/payment_success_page.dart';
import '../../features/splash/splash_page.dart';
import '../../features/trips/presentation/create_trip_page.dart';
import '../../features/shell/main_shell.dart';
import '../../features/trips/presentation/trip_page.dart';
import '../../features/voice/presentation/voice_page.dart';

/// Slide-up + fade transition used for every screen.
CustomTransitionPage<void> _page(Widget child, GoRouterState state) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, animation, secondary, child) {
        final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
            child: child,
          ),
        );
      },
    );

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', pageBuilder: (c, s) => _page(const SplashPage(), s)),
    GoRoute(path: '/home', pageBuilder: (c, s) => _page(const MainShell(), s)),
    GoRoute(path: '/onboarding', pageBuilder: (c, s) => _page(const OnboardingPage(), s)),
    GoRoute(path: '/login', pageBuilder: (c, s) => _page(const LoginPage(), s)),
    GoRoute(path: '/profile/setup', pageBuilder: (c, s) => _page(const ProfileSetupPage(), s)),
    GoRoute(path: '/profile/edit', pageBuilder: (c, s) => _page(const ProfileSetupPage(editing: true), s)),
    GoRoute(path: '/settings', pageBuilder: (c, s) => _page(const SettingsPage(), s)),
    GoRoute(path: '/join', pageBuilder: (c, s) => _page(const JoinTripPage(), s)),
    GoRoute(path: '/trip/new', pageBuilder: (c, s) => _page(const CreateTripPage(), s)),
    GoRoute(
      path: '/trip/:id',
      pageBuilder: (c, s) => _page(TripPage(tripId: s.pathParameters['id']!), s),
      routes: [
        GoRoute(
          path: 'add',
          pageBuilder: (c, s) => _page(AddExpensePage(tripId: s.pathParameters['id']!), s),
        ),
        GoRoute(
          path: 'balances',
          pageBuilder: (c, s) => _page(BalancesPage(tripId: s.pathParameters['id']!), s),
        ),
        GoRoute(
          path: 'edit',
          pageBuilder: (c, s) => _page(CreateTripPage(tripId: s.pathParameters['id']!), s),
        ),
        GoRoute(
          path: 'summary',
          pageBuilder: (c, s) => _page(SummaryPage(tripId: s.pathParameters['id']!), s),
        ),
        GoRoute(
          path: 'voice',
          pageBuilder: (c, s) => _page(
            VoicePage(tripId: s.pathParameters['id']!, fromWidget: s.uri.queryParameters['from'] == 'widget'),
            s,
          ),
        ),
        GoRoute(
          path: 'expense/:eid',
          pageBuilder: (c, s) => _page(
            ExpenseDetailPage(tripId: s.pathParameters['id']!, expenseId: s.pathParameters['eid']!),
            s,
          ),
          routes: [
            GoRoute(
              path: 'edit',
              pageBuilder: (c, s) => _page(
                AddExpensePage(tripId: s.pathParameters['id']!, expenseId: s.pathParameters['eid']!),
                s,
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'paid',
          pageBuilder: (c, s) {
            final x = (s.extra as Map<String, Object?>?) ?? const {};
            return _page(
              PaymentSuccessPage(
                tripId: s.pathParameters['id']!,
                toName: x['to'] as String? ?? '',
                amount: x['amount'] as int? ?? 0,
                app: x['app'] as String?,
                nextName: x['nextName'] as String?,
                nextAmount: x['nextAmount'] as int?,
              ),
              s,
            );
          },
        ),
      ],
    ),
  ],
);
