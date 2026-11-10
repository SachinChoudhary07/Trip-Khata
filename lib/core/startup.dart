import 'dart:async';
import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../features/cloud/cloud_sync.dart';
import '../features/trips/budget_alerts.dart';
import '../features/trips/data/trip_repository.dart';
import '../features/trips/presentation/trips_cubit.dart';
import '../features/widget/trip_widget.dart';
import 'reminders.dart';

/// Everything that used to run before the first frame. Now the app shows its
/// splash straight away and these run behind it. Each step has a time limit
/// and its own error handling, so one stuck or failing service (Firebase,
/// notifications, the widget) can never leave the app on a white screen.
class AppStartup {
  AppStartup._();

  static final _done = Completer<void>();

  /// Completes when start-up has finished (or given up on a step).
  static Future<void> get ready => _done.future;

  static Future<void> run(TripRepository repo, CloudSync cloud) async {
    try {
      await _step('notifications', Reminders.init, const Duration(seconds: 5));
      await _step('cloud', cloud.init, const Duration(seconds: 10));
      if (cloud.available) await _step('crash reports', _crashReports, const Duration(seconds: 5));
      await _step('trip services', () async {
        // App-wide trip totals: keep the home screen widget current and raise budget alerts.
        final trips = TripsCubit(repo);
        TripWidget.start(trips);
        BudgetAlerts.start(trips, repo);
      }, const Duration(seconds: 5));
    } finally {
      if (!_done.isCompleted) _done.complete();
    }
  }

  static Future<void> _step(String name, Future<void> Function() body, Duration limit) async {
    try {
      await body().timeout(limit);
    } catch (e, s) {
      debugPrint('Start-up step "$name" failed: $e');
      report(e, s, reason: 'startup: $name');
    }
  }

  static bool _crashlytics = false;

  /// Crashlytics: uncaught Flutter and platform errors from release builds.
  /// Only the error, device model, Android and app version go out, never trips.
  static Future<void> _crashReports() async {
    final c = FirebaseCrashlytics.instance;
    await c.setCrashlyticsCollectionEnabled(!kDebugMode);
    _crashlytics = true;
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      c.recordFlutterError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      c.recordError(error, stack);
      return true; // logged; keep the app running
    };
  }

  /// Sends a handled error to Crashlytics when it's on.
  static void report(Object error, StackTrace? stack, {String? reason}) {
    if (!_crashlytics) return;
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
    } catch (_) {}
  }
}
