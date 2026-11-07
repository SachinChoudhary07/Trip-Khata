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

  @override
  Set<Column> get primaryKey => {id};
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

@DriftDatabase(tables: [Trips, Members, Expenses, ExpenseShares, Settlements])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(name: 'tripkhata');

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
