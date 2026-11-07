import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/reminders.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'db/app_database.dart';
import 'features/trips/data/trip_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = TripRepository(AppDatabase());
  Reminders.init();
  runApp(TripKhataApp(repository: repo));
}

class TripKhataApp extends StatelessWidget {
  const TripKhataApp({super.key, required this.repository});
  final TripRepository repository;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: repository,
      child: MaterialApp.router(
        title: 'TripKhata',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: appRouter,
      ),
    );
  }
}
