import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';

const _uuid = Uuid();

class NewShare {
  const NewShare(this.memberId, this.share);
  final String memberId;
  final int share;
}

/// Single entry point to local data. Every screen reads from these streams,
/// so the UI updates the moment something is saved, with or without internet.
class TripRepository {
  TripRepository(this._db);
  final AppDatabase _db;

  // ---------- reads ----------

  Stream<List<Trip>> watchTrips() =>
      (_db.select(_db.trips)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Stream<Trip?> watchTrip(String id) =>
      (_db.select(_db.trips)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Stream<List<Member>> watchMembers(String tripId) => (_db.select(_db.members)
        ..where((m) => m.tripId.equals(tripId))
        ..orderBy([(m) => OrderingTerm.desc(m.isMe), (m) => OrderingTerm.asc(m.name)]))
      .watch();

  Stream<List<Member>> watchAllMembers() => _db.select(_db.members).watch();

  Stream<List<Expense>> watchExpenses(String tripId) => (_db.select(_db.expenses)
        ..where((e) => e.tripId.equals(tripId))
        ..orderBy([(e) => OrderingTerm.desc(e.spentAt)]))
      .watch();

  Stream<List<Expense>> watchAllExpenses() => _db.select(_db.expenses).watch();

  Stream<List<ExpenseShare>> watchShares(String tripId) =>
      (_db.select(_db.expenseShares)..where((s) => s.tripId.equals(tripId))).watch();

  Stream<List<ExpenseShare>> watchAllShares() => _db.select(_db.expenseShares).watch();

  Stream<List<Settlement>> watchSettlements(String tripId) =>
      (_db.select(_db.settlements)..where((s) => s.tripId.equals(tripId))).watch();

  Stream<List<Settlement>> watchAllSettlements() => _db.select(_db.settlements).watch();

  // ---------- writes ----------

  Future<String> createTrip({
    required String name,
    required String myName,
    required List<String> otherNames,
    String fromPlace = '',
    String toPlace = '',
    DateTime? startDate,
    DateTime? endDate,
    int? budget,
    String cover = 'desert',
    String? myUpiId,
  }) async {
    final tripId = _uuid.v4();
    await _db.transaction(() async {
      await _db.into(_db.trips).insert(TripsCompanion.insert(
            id: tripId,
            name: name,
            fromPlace: Value(fromPlace),
            toPlace: Value(toPlace),
            startDate: Value(startDate),
            endDate: Value(endDate),
            budget: Value(budget),
            cover: Value(cover),
          ));
      await _db.into(_db.members).insert(MembersCompanion.insert(
            id: _uuid.v4(),
            tripId: tripId,
            name: myName,
            isMe: const Value(true),
            upiId: Value(myUpiId),
          ));
      var i = 1;
      for (final n in otherNames.where((n) => n.trim().isNotEmpty)) {
        await _db.into(_db.members).insert(MembersCompanion.insert(
              id: _uuid.v4(),
              tripId: tripId,
              name: n.trim(),
              colorIndex: Value(i++ % 6),
            ));
      }
    });
    return tripId;
  }

  Future<void> addExpense({
    required String tripId,
    required String title,
    required int amount,
    required String category,
    required String paidBy,
    required List<NewShare> shares,
    String splitMode = 'equally',
    bool byVoice = false,
    DateTime? spentAt,
  }) async {
    assert(shares.fold<int>(0, (a, s) => a + s.share) == amount, 'shares must add up to amount');
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db.into(_db.expenses).insert(ExpensesCompanion.insert(
            id: id,
            tripId: tripId,
            title: title,
            amount: amount,
            category: category,
            paidBy: paidBy,
            splitMode: Value(splitMode),
            byVoice: Value(byVoice),
            spentAt: spentAt == null ? const Value.absent() : Value(spentAt),
          ));
      for (final s in shares) {
        await _db.into(_db.expenseShares).insert(ExpenseSharesCompanion.insert(
              expenseId: id,
              tripId: tripId,
              memberId: s.memberId,
              share: s.share,
            ));
      }
    });
  }

  Future<void> setMemberUpi(String memberId, String upiId) =>
      (_db.update(_db.members)..where((m) => m.id.equals(memberId)))
          .write(MembersCompanion(upiId: Value(upiId)));

  Future<void> deleteExpense(String id) =>
      (_db.delete(_db.expenses)..where((e) => e.id.equals(id))).go();

  Future<void> addSettlement({
    required String tripId,
    required String fromMember,
    required String toMember,
    required int amount,
  }) =>
      _db.into(_db.settlements).insert(SettlementsCompanion.insert(
            id: _uuid.v4(),
            tripId: tripId,
            fromMember: fromMember,
            toMember: toMember,
            amount: amount,
          ));

  /// Demo data so the app is not empty on first launch.
  Future<String> createSampleTrip() async {
    final now = DateTime.now();
    final tripId = await createTrip(
      name: 'Indore → Udaipur',
      myName: 'You',
      otherNames: const ['Rahul', 'Aman', 'Priya', 'Neha', 'Vikas'],
      fromPlace: 'Indore',
      toPlace: 'Udaipur',
      startDate: now.subtract(const Duration(days: 2)),
      endDate: now.add(const Duration(days: 1)),
      budget: 2000000,
      myUpiId: 'you@upi',
    );
    final members = await (_db.select(_db.members)..where((m) => m.tripId.equals(tripId))).get();
    String id(String name) => members.firstWhere((m) => m.name == name).id;
    final all = members.map((m) => m.id).toList();
    List<NewShare> equal(int amount, List<String> ids, String payer) {
      final base = amount ~/ ids.length;
      final left = amount - base * ids.length;
      return [for (final m in ids) NewShare(m, base + (m == (ids.contains(payer) ? payer : ids.first) ? left : 0))];
    }

    Future<void> add(String title, int rupees, String cat, String payer, {List<String>? only, int daysAgo = 0, bool voice = false}) {
      final ids = only ?? all;
      final amount = rupees * 100;
      return addExpense(
        tripId: tripId,
        title: title,
        amount: amount,
        category: cat,
        paidBy: payer,
        shares: equal(amount, ids, payer),
        byVoice: voice,
        spentAt: now.subtract(Duration(days: daysAgo, hours: daysAgo == 0 ? 1 : 0)),
      );
    }

    await add('Petrol', 2000, 'fuel', id('Neha'), daysAgo: 1);
    await add('Chai and poha', 420, 'snacks', id('Priya'), only: [id('Priya'), id('Rahul'), id('Aman'), id('Neha'), id('You')], daysAgo: 1, voice: true);
    await add('Petrol', 1500, 'fuel', id('Rahul'), voice: true);
    await add('Toll plaza', 340, 'toll', id('Rahul'), voice: true);
    await add('Dal baati churma', 1860, 'food', id('Aman'), voice: true);
    await add('Hotel, 2 rooms', 6400, 'stay', id('Vikas'));
    await add('Keychains', 100, 'shopping', id('Rahul'), only: [id('Rahul'), id('Aman')]);
    return tripId;
  }
}
