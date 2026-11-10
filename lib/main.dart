import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'core/reminders.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'db/app_database.dart';
import 'features/cloud/cloud_sync.dart';
import 'features/trips/budget_alerts.dart';
import 'features/trips/presentation/trips_cubit.dart';
import 'features/widget/trip_widget.dart';
import 'features/trips/data/trip_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = TripRepository(AppDatabase());
  final cloud = CloudSync(repo);
  await Reminders.init();
  await cloud.init(); // no-op when this build has no Firebase settings
  if (cloud.available) await _crashReports();
  // App-wide trip totals: keep the home screen widget current and raise budget alerts.
  final trips = TripsCubit(repo);
  TripWidget.start(trips);
  BudgetAlerts.start(trips, repo);
  // Notification taps are routed from the splash screen once home is up.
  runApp(TripKhataApp(repository: repo, cloud: cloud));
}

/// Crashlytics: uncaught Flutter and platform errors from release builds.
/// Only the error, device model, Android and app version go out, never trips.
Future<void> _crashReports() async {
  try {
    final c = FirebaseCrashlytics.instance;
    await c.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = c.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      c.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Crashlytics off: $e');
  }
}

class TripKhataApp extends StatelessWidget {
  const TripKhataApp({super.key, required this.repository, required this.cloud});
  final TripRepository repository;
  final CloudSync cloud;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: repository,
      child: ChangeNotifierProvider.value(
        value: cloud,
        child: MaterialApp.router(
        title: 'TripKhata',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: appRouter,
        ),
      ),
    );
  }
}
