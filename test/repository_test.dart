import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripkhata/db/app_database.dart';
import 'package:tripkhata/features/settle/domain/settlement_calculator.dart';
import 'package:tripkhata/features/trips/data/trip_repository.dart';

void main() {
  late AppDatabase db;
  late TripRepository repo;

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    repo = TripRepository(db);
  });
  tearDown(() => db.close());

  Future<Map<String, String>> ids(String tripId) async {
    final m = await (db.select(db.members)..where((x) => x.tripId.equals(tripId))).get();
    return {for (final x in m) x.name: x.id};
  }

  test('createTrip adds me plus the others, skipping blanks', () async {
    final id = await repo.createTrip(name: 'Goa', myName: 'Sachin', otherNames: ['Rahul', ' ', 'Aman']);
    final m = await ids(id);
    expect(m.keys, containsAll(['Sachin', 'Rahul', 'Aman']));
    expect(m.length, 3);
    final me = await (db.select(db.members)..where((x) => x.isMe.equals(true))).getSingle();
    expect(me.name, 'Sachin');
  });

  test('keychain: only buyers share it, balances match the domain maths', () async {
    final id = await repo.createTrip(name: 'T', myName: 'Priya', otherNames: ['Rahul', 'Aman']);
    final m = await ids(id);
    await repo.addExpense(
      tripId: id,
      title: 'Keychains',
      amount: 10000,
      category: 'shopping',
      paidBy: m['Rahul']!,
      shares: [NewShare(m['Rahul']!, 5000), NewShare(m['Aman']!, 5000)],
    );
    final shares = await db.select(db.expenseShares).get();
    expect(shares.length, 2);
    final e = await db.select(db.expenses).getSingle();
    final b = SettlementCalculator.balances(
      memberIds: m.values,
      payments: [PaymentEntry(e.paidBy, e.amount)],
      shares: shares.map((s) => ShareEntry(s.memberId, s.share)),
    );
    expect(b[m['Priya']], 0);
    expect(b[m['Rahul']], 5000);
    expect(b[m['Aman']], -5000);
  });

  test('updateExpense replaces shares in one go', () async {
    final id = await repo.createTrip(name: 'T', myName: 'A', otherNames: ['B', 'C']);
    final m = await ids(id);
    await repo.addExpense(
      tripId: id,
      title: 'Lunch',
      amount: 9000,
      category: 'food',
      paidBy: m['A']!,
      shares: [NewShare(m['A']!, 3000), NewShare(m['B']!, 3000), NewShare(m['C']!, 3000)],
    );
    final e = await db.select(db.expenses).getSingle();
    await repo.updateExpense(
      id: e.id,
      title: 'Lunch (2 people)',
      amount: 8000,
      category: 'food',
      paidBy: m['B']!,
      shares: [NewShare(m['A']!, 4000), NewShare(m['B']!, 4000)],
      splitMode: 'byAmount',
    );
    final after = await db.select(db.expenses).getSingle();
    final shares = await repo.getShares(e.id);
    expect(after.title, 'Lunch (2 people)');
    expect(after.amount, 8000);
    expect(after.paidBy, m['B']);
    expect(after.splitMode, 'byAmount');
    expect(shares.map((s) => s.memberId), unorderedEquals([m['A'], m['B']]));
    expect(shares.fold<int>(0, (a, s) => a + s.share), 8000);
  });

  test('addMembers ignores names already in the trip', () async {
    final id = await repo.createTrip(name: 'T', myName: 'A', otherNames: ['Rahul']);
    await repo.addMembers(id, ['rahul', 'Neha', 'Neha ']);
    final names = (await ids(id)).keys;
    expect(names, unorderedEquals(['A', 'Rahul', 'Neha']));
  });

  test('deleting an expense or a trip leaves no orphaned rows', () async {
    final id = await repo.createTrip(name: 'T', myName: 'A', otherNames: ['B']);
    final m = await ids(id);
    await repo.addExpense(
      tripId: id,
      title: 'X',
      amount: 200,
      category: 'other',
      paidBy: m['A']!,
      shares: [NewShare(m['A']!, 100), NewShare(m['B']!, 100)],
    );
    final e = await db.select(db.expenses).getSingle();
    await repo.deleteExpense(e.id);
    expect(await db.select(db.expenseShares).get(), isEmpty, reason: 'shares go with the expense');

    await repo.addExpense(
      tripId: id,
      title: 'Y',
      amount: 200,
      category: 'other',
      paidBy: m['A']!,
      shares: [NewShare(m['A']!, 100), NewShare(m['B']!, 100)],
    );
    await repo.deleteTrip(id);
    expect(await db.select(db.trips).get(), isEmpty);
    expect(await db.select(db.members).get(), isEmpty);
    expect(await db.select(db.expenses).get(), isEmpty);
    expect(await db.select(db.expenseShares).get(), isEmpty);
  });

  test('sample trip is internally consistent', () async {
    final id = await repo.createSampleTrip();
    final expenses = await (db.select(db.expenses)..where((e) => e.tripId.equals(id))).get();
    final shares = await db.select(db.expenseShares).get();
    for (final e in expenses) {
      final sum = shares.where((s) => s.expenseId == e.id).fold<int>(0, (a, s) => a + s.share);
      expect(sum, e.amount, reason: e.title);
    }
    final places = await (db.select(db.places)..where((p) => p.tripId.equals(id))).get();
    expect(places.length, 6);
  });

  test('profile save is an upsert on a single row', () async {
    expect(await repo.getProfile(), isNull);
    await repo.saveProfile(name: 'Sachin', upiId: 'sachin@okaxis');
    await repo.saveProfile(name: 'Sachin C', upiId: 'sachin@okaxis', colorIndex: 2);
    final p = await repo.getProfile();
    expect(p!.name, 'Sachin C');
    expect(p.colorIndex, 2);
    expect(await db.select(db.profiles).get(), hasLength(1));
  });

  test('CSV export has a header and one row per expense', () async {
    final id = await repo.createTrip(name: 'Goa "2026"', myName: 'A', otherNames: ['B']);
    final m = await ids(id);
    await repo.addExpense(
      tripId: id,
      title: 'Petrol',
      amount: 150000,
      category: 'fuel',
      paidBy: m['A']!,
      shares: [NewShare(m['A']!, 75000), NewShare(m['B']!, 75000)],
    );
    final lines = (await repo.exportCsv()).trim().split('\n');
    expect(lines.first, startsWith('trip,date,title'));
    expect(lines.length, 2);
    expect(lines[1], contains('"Goa ""2026"""'));
    expect(lines[1], contains('1500.00'));
  });

  test('shared trip: edits are queued, remote rows round-trip, remote delete wins', () async {
    final id = await repo.createTrip(name: 'T', myName: 'A', otherNames: ['B']);
    final m = await ids(id);
    // Not shared yet: nothing queued.
    await repo.addSettlement(tripId: id, fromMember: m['B']!, toMember: m['A']!, amount: 100);
    expect(await db.select(db.outbox).get(), isEmpty);

    await repo.markShared(id, 'ABC234', 'uid-a');
    await repo.addExpense(
      tripId: id,
      title: 'Petrol',
      amount: 2000,
      category: 'fuel',
      paidBy: m['A']!,
      shares: [NewShare(m['A']!, 1000), NewShare(m['B']!, 1000)],
    );
    final queued = await db.select(db.outbox).get();
    expect(queued.map((o) => o.entity), ['expense']);

    // Export -> apply into a second phone's database gives the same expense.
    final exported = await repo.exportEntity('expense', queued.single.entityId);
    final db2 = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    addTearDown(db2.close);
    final repo2 = TripRepository(db2);
    await repo2.applyRemoteTrip(id, (await repo.exportTripDoc(id))!);
    for (final mem in (await repo.exportTrip(id))['member']!) {
      await repo2.applyRemote(id, 'member', mem['id'] as String, mem, myUid: 'uid-a');
    }
    await repo2.applyRemote(id, 'expense', exported!['id'] as String, exported);
    final e2 = await db2.select(db2.expenses).getSingle();
    expect(e2.amount, 2000);
    expect((await db2.select(db2.expenseShares).get()).length, 2);
    expect(await db2.select(db2.outbox).get(), isEmpty, reason: 'remote writes are never re-queued');
    final me2 = await (db2.select(db2.members)..where((x) => x.isMe.equals(true))).getSingle();
    expect(me2.name, 'A', reason: 'uid match marks "me" on the other phone');

    await repo2.applyRemote(id, 'expense', e2.id, {'deleted': true, 'updatedAt': DateTime.now().millisecondsSinceEpoch});
    expect(await db2.select(db2.expenses).get(), isEmpty);
    expect(await db2.select(db2.expenseShares).get(), isEmpty);
  });
}
