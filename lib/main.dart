import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/startup.dart';
import 'core/theme/app_theme.dart';
import 'db/app_database.dart';
import 'features/cloud/cloud_sync.dart';
import 'features/cloud/invite_links.dart';
import 'features/trips/data/trip_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = TripRepository(AppDatabase());
  final cloud = CloudSync(repo);
  DeepLinks.init(); // invite links; held until the home screen is up
  // Show the app first; services start behind the splash screen.
  runApp(TripKhataApp(repository: repo, cloud: cloud));
  unawaited(AppStartup.run(repo, cloud));
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
