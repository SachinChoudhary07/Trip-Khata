import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/router/app_router.dart';
import '../../core/utils/money.dart';
import '../trips/data/trip_repository.dart';
import '../trips/presentation/trips_cubit.dart';

/// The Android home screen widget: shows the active trip and has a mic button
/// (and a keyboard button) that open straight into adding an expense.
///
/// The native side is `TripWidgetProvider` (written into android/ by
/// tool/patch_android.dart). It reads the values saved here and fires
/// `tripkhata://widget/voice` or `tripkhata://widget/type` when tapped.
class TripWidget {
  TripWidget._();

  static const _provider = 'com.tripkhata.tripkhata.TripWidgetProvider';

  static StreamSubscription<TripsState>? _sub;
  static String _last = '';

  /// Keeps the widget in step with the active trip. Call once at start-up.
  static void start(TripsCubit trips) {
    if (defaultTargetPlatform != TargetPlatform.android || _sub != null) return;
    _sub = trips.stream.listen(_push);
  }

  static Future<void> _push(TripsState s) async {
    if (s.loading) return;
    final a = s.active;
    final name = a?.trip.name ?? 'No active trip';
    final line = a == null
        ? (s.trips.isEmpty ? 'Tap to start a trip' : 'Tap to pick the trip you’re on')
        : '${formatPaise(a.total)} spent · ${_balance(a.myBalance)}';
    final key = '$name|$line|${a != null}';
    if (key == _last) return;
    _last = key;
    try {
      await HomeWidget.saveWidgetData<String>('tk_trip_name', name);
      await HomeWidget.saveWidgetData<String>('tk_trip_line', line);
      await HomeWidget.saveWidgetData<bool>('tk_has_trip', a != null);
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } catch (e) {
      debugPrint('Widget update failed: $e');
    }
  }

  static String _balance(int b) => switch (b) {
        > 0 => 'you get ${formatPaise(b)}',
        < 0 => 'you owe ${formatPaise(-b)}',
        _ => 'all settled',
      };

  /// What a widget tap asked for: 'voice', 'type' or 'open'; null if the app
  /// wasn't opened from the widget.
  static String? actionOf(Uri? uri) {
    if (uri == null || uri.scheme != 'tripkhata' || uri.host != 'widget') return null;
    return uri.pathSegments.isEmpty ? 'open' : uri.pathSegments.first;
  }

  /// The tap that cold-started the app, if any.
  static Future<String?> launchAction() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return actionOf(await HomeWidget.initiallyLaunchedFromHomeWidget().timeout(const Duration(seconds: 3)));
    } catch (_) {
      return null;
    }
  }

  /// Taps while the app is already running.
  static Stream<String> get clicks => defaultTargetPlatform != TargetPlatform.android
      ? const Stream.empty()
      : HomeWidget.widgetClicked.map(actionOf).where((a) => a != null).cast<String>();

  static StreamSubscription<String>? _clickSub;

  /// Routes widget taps once the home screen is up (called from splash).
  static void listenClicks(TripRepository repo) {
    _clickSub ??= clicks.listen((a) => open(a, repo));
  }

  /// Mic → voice screen of the active trip (it starts listening by itself);
  /// keyboard → the add-expense form. No active trip → home, where the user
  /// picks one (or creates the first).
  static Future<void> open(String action, TripRepository repo) async {
    final trip = await repo.getActiveTrip();
    if (trip == null) {
      appRouter.go('/home');
      final any = (await repo.watchTrips().first).isNotEmpty;
      if (!any) appRouter.push('/trip/new');
      return;
    }
    switch (action) {
      case 'voice':
        appRouter.push('/trip/${trip.id}/voice?from=widget');
      case 'type':
        appRouter.push('/trip/${trip.id}/add');
      default:
        appRouter.push('/trip/${trip.id}');
    }
  }

  static Future<void> dispose() async {
    await _clickSub?.cancel();
    _clickSub = null;
    await _sub?.cancel();
    _sub = null;
  }
}
