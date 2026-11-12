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

  test('profile save is an upsert on a single row', () async {
    expect(await repo.getProfile(), isNull);
    await repo.saveProfile(name: 'Sachin', upiId: 'sachin@okaxis');
    await repo.saveProfile(name: 'Sachin C', upiId: 'sachin@okaxis', colorIndex: 2);
    final p = await repo.getProfile();
    expect(p!.name, 'Sachin C');
    expect(p.colorIndex, 2);
    expect(await db.select(db.profiles).get(), hasLength(1));
  });

  test('friends-activity notifications are on by default and can be turned off', () async {
    await repo.saveProfile(name: 'Sachin', upiId: '');
    expect((await repo.getProfile())!.notifyActivity, isTrue);
    await repo.updateSettings(notifyActivity: false);
    final p = await repo.getProfile();
    expect(p!.notifyActivity, isFalse);
    expect(p.reminders, isTrue);
  });

  test('one active trip at a time: newest trip takes over, deleting it clears it', () async {
    await repo.saveProfile(name: 'Sachin', upiId: '');
    final goa = await repo.createTrip(name: 'Goa', myName: 'Sachin', otherNames: ['Rahul']);
    expect((await repo.getActiveTrip())!.id, goa);
    final manali = await repo.createTrip(name: 'Manali', myName: 'Sachin', otherNames: ['Aman']);
    expect((await repo.getActiveTrip())!.id, manali);
    await repo.setActiveTrip(goa);
    expect((await repo.getActiveTrip())!.name, 'Goa');
    await repo.deleteTrip(manali); // not active: Goa stays
    expect((await repo.getActiveTrip())!.id, goa);
    await repo.deleteTrip(goa);
    expect(await repo.getActiveTrip(), isNull);
    expect((await repo.getProfile())!.activeTripId, isNull);
  });

  test('bill photos: pending until uploaded, path travels with the expense, a new photo drops the stale copy', () async {
    final id = await repo.createTrip(name: 'T', myName: 'A', otherNames: ['B']);
    final m = await ids(id);
    await repo.markShared(id, 'BILL22', 'uid-a');
    await repo.addExpense(
      tripId: id,
      title: 'Hotel',
      amount: 500000,
      category: 'stay',
      paidBy: m['A']!,
      shares: [NewShare(m['A']!, 250000), NewShare(m['B']!, 250000)],
    );
    final eid = (await db.select(db.expenses).getSingle()).id;
    await repo.setBillPath(eid, '/tmp/bill.jpg');
    expect((await repo.pendingBillUploads()).map((e) => e.id), [eid]);
    await repo.setBillRemote(eid, 'tripkhata/$id/bills/$eid-1.jpg');
    expect(await repo.pendingBillUploads(), isEmpty);
    final exported = (await repo.exportEntity('expense', eid))!;
    expect(exported['bill'], 'tripkhata/$id/bills/$eid-1.jpg');

    // Friend's phone: gets the path, downloads later.
    final db2 = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    addTearDown(db2.close);
    final repo2 = TripRepository(db2);
    await repo2.applyRemoteTrip(id, (await repo.exportTripDoc(id))!);
    await repo2.applyRemote(id, 'expense', eid, exported);
    expect((await repo2.getExpense(eid))!.billRemote, exported['bill']);
    await repo2.setLocalBill(eid, '/tmp/friend-copy.jpg');
    expect(await db2.select(db2.outbox).get(), isEmpty, reason: 'a downloaded copy is not shared back');

    // The photo is replaced: the old local copy is dropped.
    await repo2.applyRemote(id, 'expense', eid, {
      ...exported,
      'bill': 'tripkhata/$id/bills/$eid-2.jpg',
      'updatedAt': DateTime.now().add(const Duration(seconds: 5)).millisecondsSinceEpoch,
    });
    final e2 = (await repo2.getExpense(eid))!;
    expect(e2.billPath, isNull);
    expect(e2.billRemote, 'tripkhata/$id/bills/$eid-2.jpg');
  });

  test('budget alert level is remembered per trip; eraseAll clears the phone', () async {
    await repo.saveProfile(name: 'A', upiId: '');
    final id = await repo.createTrip(name: 'T', myName: 'A', otherNames: ['B'], budget: 1000000);
    expect((await repo.getTrip(id))!.budgetAlerted, 0);
    await repo.setBudgetAlerted(id, 80);
    expect((await repo.getTrip(id))!.budgetAlerted, 80);
    expect(await db.select(db.outbox).get(), isEmpty);
    await repo.eraseAll();
    expect(await db.select(db.trips).get(), isEmpty);
    expect(await repo.getProfile(), isNull);
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

  test('updateTrip changes details, queues the trip when shared, deleteTrip clears the outbox', () async {
    final id = await repo.createTrip(name: 'Old', myName: 'A', otherNames: []);
    await repo.updateTrip(id, name: 'New name', fromPlace: 'Indore', toPlace: 'Goa', budget: 500000, cover: 'beach');
    var t = (await repo.getTrip(id))!;
    expect([t.name, t.fromPlace, t.toPlace, t.budget, t.cover], ['New name', 'Indore', 'Goa', 500000, 'beach']);
    expect(await db.select(db.outbox).get(), isEmpty, reason: 'not shared: nothing to sync');

    await repo.markShared(id, 'XYZ789', 'uid');
    await repo.updateTrip(id, name: 'Shared');
    expect((await db.select(db.outbox).get()).map((o) => o.entity), ['trip']);

    await repo.deleteTrip(id);
    expect(await repo.getTrip(id), isNull);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('photos: wait for upload only in shared trips, sync as uploader, remote delete drops them', () async {
    final id = await repo.createTrip(name: 'Manali', myName: 'Sachin', otherNames: ['Rahul']);
    await repo.addPhoto(
        id: 'photo-0001', tripId: id, localPath: '/x/a.jpg', thumbPath: '/x/a_t.jpg', width: 2048, height: 1536, bytes: 400000);
    final me = await (db.select(db.members)..where((x) => x.isMe.equals(true))).getSingle();
    expect((await repo.getPhoto('photo-0001'))!.memberId, me.id);
    expect(await repo.pendingPhotoUploads(), isEmpty); // not shared: stays on the phone

    await repo.markShared(id, 'PHO234', 'uid-a');
    expect((await repo.pendingPhotoUploads()).map((p) => p.id), ['photo-0001']);
    expect(await repo.exportEntity('photo', 'photo-0001'), isNull); // not in the cloud until uploaded

    await repo.setPhotoUploaded('photo-0001', 'tripkhata/$id/photos/photo-0001.jpg', 'uid-a');
    expect(await repo.pendingPhotoUploads(), isEmpty);
    final out = await db.select(db.outbox).get();
    expect(out.where((o) => o.entity == 'photo').map((o) => o.entityId), ['photo-0001']);
    final doc = (await repo.exportEntity('photo', 'photo-0001'))!;
    expect(doc['uploaderUid'], 'uid-a');
    expect(doc['key'], 'tripkhata/$id/photos/photo-0001.jpg');

    // A friend's photo arrives; it keeps no local file until fetched.
    await repo.applyRemote(id, 'photo', 'photo-0002', {
      'key': 'tripkhata/$id/photos/photo-0002.jpg',
      'uploaderUid': 'uid-b',
      'width': 1000,
      'height': 800,
      'createdAt': 1700000000000,
    });
    final friend = (await repo.getPhoto('photo-0002'))!;
    expect(friend.localPath, isNull);
    expect(friend.uploaderUid, 'uid-b');
    await repo.setPhotoFiles('photo-0002', thumbPath: '/x/b_t.jpg');
    await repo.applyRemote(id, 'photo', 'photo-0002', {'key': 'tripkhata/$id/photos/photo-0002.jpg', 'uploaderUid': 'uid-b'});
    expect((await repo.getPhoto('photo-0002'))!.thumbPath, '/x/b_t.jpg'); // a remote update keeps the cached file

    await repo.removeRemotePhoto('photo-0002');
    expect(await repo.getPhoto('photo-0002'), isNull);

    await repo.deletePhoto('photo-0001');
    expect(await repo.getPhoto('photo-0001'), isNull);
    final deletes = (await db.select(db.outbox).get()).where((o) => o.entity == 'photo' && o.op == 'delete');
    expect(deletes.length, 1);

    await repo.addPhoto(id: 'photo-0003', tripId: id, localPath: '/x/c.jpg', thumbPath: '/x/c_t.jpg', width: 1, height: 1, bytes: 1);
    await repo.deleteTrip(id);
    expect(await db.select(db.tripPhotos).get(), isEmpty);
  });
}
