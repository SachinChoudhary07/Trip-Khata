import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripkhata/features/cloud/cloud_sync.dart';
import 'package:tripkhata/core/theme/app_theme.dart';
import 'package:tripkhata/db/app_database.dart';
import 'package:tripkhata/features/shell/main_shell.dart';
import 'package:tripkhata/features/trips/data/trip_repository.dart';

void main() {
  testWidgets('empty home shows the first-trip actions and the bottom bar', (tester) async {
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    addTearDown(db.close);
    final repo = TripRepository(db);
    await tester.pumpWidget(RepositoryProvider.value(
      value: repo,
      child: ChangeNotifierProvider.value(
        value: CloudSync(repo), // not initialised: cloud features stay hidden
        child: MaterialApp(theme: AppTheme.light(), home: const MainShell()),
      ),
    ));
    // Let the drift streams emit and the fade-ins run.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Start a trip'), findsWidgets);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
