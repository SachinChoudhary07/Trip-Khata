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

  /// Highest budget alert already shown on this phone: 0, 80 or 100 (%).
  IntColumn get budgetAlerted => integer().withDefault(const Constant(0))();
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

  /// Firebase Storage path of the bill photo, for shared trips.
  TextColumn get billRemote => text().nullable()();
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

  /// Notify at 80% and 100% of a trip's budget.
  BoolColumn get notifyBudget => boolean().withDefault(const Constant(true))();

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

/// Trip photos, compressed on the phone. In a shared trip they are uploaded to
/// Cloudflare R2 and everyone in the trip sees them.
class TripPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text().references(Trips, #id, onDelete: KeyAction.cascade)();

  /// Member who added the photo (on the phone that added it).
  TextColumn get memberId => text().nullable()();

  /// Firebase uid of the person who uploaded it. Only they can delete it.
  TextColumn get uploaderUid => text().nullable()();

  /// R2 key of the photo once uploaded (the thumbnail is the same key with
  /// `_t` before `.jpg`). Null while it waits to be uploaded.
  TextColumn get remoteKey => text().nullable()();

  /// Compressed photo and grid thumbnail on this phone, when present.
  TextColumn get localPath => text().nullable()();
  TextColumn get thumbPath => text().nullable()();

  IntColumn get width => integer().withDefault(const Constant(0))();
  IntColumn get height => integer().withDefault(const Constant(0))();
  IntColumn get bytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Trips, Members, Expenses, ExpenseShares, Settlements, Profiles, Places, Outbox, TripPhotos])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(name: 'tripkhata');

  @override
  int get schemaVersion => 8;

  /// Migrations must survive being half-applied or a table that was created
  /// with today's columns (createTable uses the current schema), so every
  /// step checks first instead of failing with "duplicate column".
  Future<bool> _hasTable(String name) async =>
      (await customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
              variables: [Variable.withString(name)])
          .get())
          .isNotEmpty;

  Future<void> _createTable(Migrator m, TableInfo<Table, dynamic> table) async {
    if (!await _hasTable(table.actualTableName)) await m.createTable(table);
  }

  Future<void> _addColumn(Migrator m, TableInfo<Table, dynamic> table, GeneratedColumn<Object> column) async {
    final cols = await customSelect('PRAGMA table_info(${table.actualTableName})').get();
    if (cols.any((r) => r.read<String>('name') == column.name)) return;
    await m.addColumn(table, column);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await _createTable(m, profiles);
            await _createTable(m, places);
            await _addColumn(m, expenses, expenses.placeId);
          }
          if (from < 3) {
            await _addColumn(m, expenses, expenses.billPath);
          }
          if (from < 4) {
            await _addColumn(m, trips, trips.joinCode);
            await _addColumn(m, members, members.uid);
            await _createTable(m, outbox);
          }
          if (from < 5) {
            await _addColumn(m, profiles, profiles.notifyActivity);
          }
          if (from < 6) {
            await _addColumn(m, profiles, profiles.activeTripId);
            // Existing users: the newest trip becomes the active one.
            await customStatement(
              'UPDATE profiles SET active_trip_id = (SELECT id FROM trips ORDER BY created_at DESC LIMIT 1)',
            );
          }
          if (from < 7) {
            await _addColumn(m, expenses, expenses.billRemote);
            await _addColumn(m, trips, trips.budgetAlerted);
            await _addColumn(m, profiles, profiles.notifyBudget);
            // Don't alert about budgets that were already crossed before this update.
            await customStatement('''
              UPDATE trips SET budget_alerted = CASE
                WHEN budget IS NULL OR budget <= 0 THEN 0
                WHEN (SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE trip_id = trips.id) >= budget THEN 100
                WHEN (SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE trip_id = trips.id) * 10 >= budget * 8 THEN 80
                ELSE 0 END
            ''');
          }
          if (from < 8) {
            await _createTable(m, tripPhotos);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
