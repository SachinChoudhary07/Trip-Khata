import 'dart:async';

import '../../core/reminders.dart';
import '../../core/utils/money.dart';
import 'data/trip_repository.dart';
import 'presentation/trips_cubit.dart';

/// Notifies once when a trip's spending crosses 80% and again at 100% of
/// its budget. Works for your own expenses and for friends' synced ones,
/// whenever the app is running. The level shown is kept per trip, so
/// deleting expenses (or raising the budget) quietly re-arms it.
class BudgetAlerts {
  BudgetAlerts._();

  static StreamSubscription<TripsState>? _sub;
  static bool _busy = false;
  static TripsState? _next;

  static void start(TripsCubit trips, TripRepository repo) {
    _sub ??= trips.stream.listen((s) => _run(s, repo));
  }

  /// One check at a time, always on the latest state, so a burst of synced
  /// expenses can't raise the same alert twice.
  static Future<void> _run(TripsState s, TripRepository repo) async {
    _next = s;
    if (_busy) return;
    _busy = true;
    try {
      while (_next != null) {
        final state = _next!;
        _next = null;
        await _check(state, repo);
      }
    } finally {
      _busy = false;
    }
  }

  /// 0, 80 or 100.
  static int levelFor(int total, int? budget) {
    if (budget == null || budget <= 0) return 0;
    if (total >= budget) return 100;
    if (total * 10 >= budget * 8) return 80;
    return 0;
  }

  static Future<void> _check(TripsState s, TripRepository repo) async {
    if (s.loading) return;
    bool? enabled;
    for (final t in s.trips) {
      final level = levelFor(t.total, t.trip.budget);
      final shown = t.trip.budgetAlerted;
      if (level == shown) continue;
      await repo.setBudgetAlerted(t.trip.id, level);
      if (level < shown) continue; // spending went down: re-arm silently
      enabled ??= (await repo.getProfile())?.notifyBudget ?? true;
      if (!enabled) continue;
      final budget = t.trip.budget!;
      final (title, body) = level == 100
          ? ('${t.trip.name} is over budget', '${formatPaise(t.total)} spent of ${formatPaise(budget)}')
          : ('${t.trip.name}: 80% of budget used',
              '${formatPaise(t.total)} spent of ${formatPaise(budget)} · ${formatPaise(budget - t.total)} left');
      await Reminders.showBudget(tripId: t.trip.id, title: title, body: body);
    }
  }
}
