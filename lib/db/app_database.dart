import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// All money columns are in paise (integers).

class Trips extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get fromPlace => text().withDefault(const Constant(''))();
  TextColumn get toPlace => text().withDefault(const Constant(''))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get budget => integer().nullable()();
  TextColumn get cover => text().withDefault(const Constant('desert'))();

  /// Set when the trip is shared to the cloud; friends join with this code.
  TextColumn get joinCode => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Members extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get upiId => text().nullable()();
  IntColumn get colorIndex => integer().withDefault(const Constant(0))();
  BoolColumn get isMe => boolean().withDefault(const Constant(false))();

  /// Firebase uid of the person who claimed this member (shared trips only).
  TextColumn get uid => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local changes waiting to be pushed to the cloud (shared trips only).
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get tripId => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()();
}

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  IntColumn get amount => integer()();
  TextColumn get category => text()();
  TextColumn get paidBy => text().references(Members, #id)();
  TextColumn get splitMode => text().withDefault(const Constant('equally'))();
  BoolColumn get byVoice => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  TextColumn get placeId => text().nullable()();
  TextColumn get billPath => text().nullable()();
  DateTimeColumn get spentAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ExpenseShares extends Table {
  TextColumn get expenseId => text().references(Expenses, #id, onDelete: KeyAction.cascade)();
  TextColumn get tripId => text()();
  TextColumn get memberId => text().references(Members, #id)();
  IntColumn get share => integer()();

  @override
  Set<Column> get primaryKey => {expenseId, memberId};
}

class Settlements extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get fromMember => text().references(Members, #id)();
  TextColumn get toMember => text().references(Members, #id)();
  IntColumn get amount => integer()();
  DateTimeColumn get paidAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row table (id = 1) with the phone owner's profile and settings.
class Profiles extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get name => text()();
  TextColumn get upiId => text().nullable()();
  IntColumn get colorIndex => integer().withDefault(const Constant(0))();
  TextColumn get voiceLang => text().withDefault(const Constant('hi'))();
  BoolColumn get reminders => boolean().withDefault(const Constant(true))();

  /// Notify when friends add or change expenses in shared trips.
  BoolColumn get notifyActivity => boolean().withDefault(const Constant(true))();

  /// The one trip quick-add, voice and the home screen widget write to.
  /// Kept per phone (not synced): each friend picks their own.
  TextColumn get activeTripId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Check-ins: hotels, dhabas, petrol pumps, sights along the route.
class Places extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get type => text()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get visitedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Trips, Members, Expenses, ExpenseShares, Settlements, Profiles, Places, Outbox])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(name: 'tripkhata');

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(profiles);
            await m.createTable(places);
            await m.addColumn(expenses, expenses.placeId);
          }
          if (from < 3) {
            await m.addColumn(expenses, expenses.billPath);
          }
          if (from < 4) {
            await m.addColumn(trips, trips.joinCode);
            await m.addColumn(members, members.uid);
            await m.createTable(outbox);
          }
          if (from < 5) {
            await m.addColumn(profiles, profiles.notifyActivity);
          }
          if (from < 6) {
            await m.addColumn(profiles, profiles.activeTripId);
            // Existing users: the newest trip becomes the active one.
            await customStatement(
              'UPDATE profiles SET active_trip_id = (SELECT id FROM trips ORDER BY created_at DESC LIMIT 1)',
            );
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
