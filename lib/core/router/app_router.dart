import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/expenses/presentation/add_expense_page.dart';
import '../../features/expenses/presentation/expense_detail_page.dart';
import '../../features/settle/presentation/balances_page.dart';
import '../../features/settle/presentation/payment_success_page.dart';
import '../../features/splash/splash_page.dart';
import '../../features/trips/presentation/create_trip_page.dart';
import '../../features/trips/presentation/home_page.dart';
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
    GoRoute(path: '/home', pageBuilder: (c, s) => _page(const HomePage(), s)),
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
          path: 'voice',
          pageBuilder: (c, s) => _page(VoicePage(tripId: s.pathParameters['id']!), s),
        ),
        GoRoute(
          path: 'expense/:eid',
          pageBuilder: (c, s) => _page(
            ExpenseDetailPage(tripId: s.pathParameters['id']!, expenseId: s.pathParameters['eid']!),
            s,
          ),
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
