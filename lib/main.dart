import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'core/reminders.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'db/app_database.dart';
import 'features/cloud/cloud_sync.dart';
import 'features/widget/trip_widget.dart';
import 'features/trips/data/trip_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = TripRepository(AppDatabase());
  final cloud = CloudSync(repo);
  await Reminders.init();
  await cloud.init(); // no-op when this build has no Firebase settings
  TripWidget.start(repo); // keeps the home screen widget showing the active trip
  // Notification taps are routed from the splash screen once home is up.
  runApp(TripKhataApp(repository: repo, cloud: cloud));
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
