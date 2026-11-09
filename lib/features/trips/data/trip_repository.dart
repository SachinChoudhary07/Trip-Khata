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

  Stream<Profile?> watchProfile() =>
      (_db.select(_db.profiles)..where((p) => p.id.equals(1))).watchSingleOrNull();

  Future<Profile?> getProfile() =>
      (_db.select(_db.profiles)..where((p) => p.id.equals(1))).getSingleOrNull();

  Stream<List<Place>> watchPlaces(String tripId) => (_db.select(_db.places)
        ..where((p) => p.tripId.equals(tripId))
        ..orderBy([(p) => OrderingTerm.asc(p.visitedAt)]))
      .watch();

  // ---------- writes ----------

  Future<void> saveProfile({
    required String name,
    String? upiId,
    int colorIndex = 0,
    String? voiceLang,
    bool? reminders,
  }) =>
      _db.into(_db.profiles).insertOnConflictUpdate(ProfilesCompanion(
            id: const Value(1),
            name: Value(name),
            upiId: Value(upiId),
            colorIndex: Value(colorIndex),
            voiceLang: voiceLang == null ? const Value.absent() : Value(voiceLang),
            reminders: reminders == null ? const Value.absent() : Value(reminders),
          ));

  Future<void> updateSettings({String? voiceLang, bool? reminders}) =>
      (_db.update(_db.profiles)..where((p) => p.id.equals(1))).write(ProfilesCompanion(
        voiceLang: voiceLang == null ? const Value.absent() : Value(voiceLang),
        reminders: reminders == null ? const Value.absent() : Value(reminders),
      ));

  Future<String> addPlace({
    required String tripId,
    required String name,
    required String type,
    double? lat,
    double? lng,
    String? note,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.places).insert(PlacesCompanion.insert(
          id: id,
          tripId: tripId,
          name: name,
          type: type,
          lat: Value(lat),
          lng: Value(lng),
          note: Value(note),
        ));
    await _queue(tripId, 'place', id);
    return id;
  }

  /// All trips as CSV: one row per expense, with each person's share.
  Future<String> exportCsv() async {
    final trips = await _db.select(_db.trips).get();
    final members = {for (final m in await _db.select(_db.members).get()) m.id: m};
    final expenses = await (_db.select(_db.expenses)..orderBy([(e) => OrderingTerm.asc(e.spentAt)])).get();
    final shares = await _db.select(_db.expenseShares).get();
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    final tripName = {for (final t in trips) t.id: t.name};
    final b = StringBuffer('trip,date,title,category,amount_inr,paid_by,split_between\n');
    for (final e in expenses) {
      final who = shares
          .where((s) => s.expenseId == e.id)
          .map((s) => '${members[s.memberId]?.name ?? '?'} ${(s.share / 100).toStringAsFixed(2)}')
          .join('; ');
      b.writeln([
        q(tripName[e.tripId] ?? ''),
        e.spentAt.toIso8601String().substring(0, 16).replaceFirst('T', ' '),
        q(e.title),
        e.category,
        (e.amount / 100).toStringAsFixed(2),
        q(members[e.paidBy]?.name ?? ''),
        q(who),
      ].join(','));
    }
    return b.toString();
  }

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
    String? placeId,
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
            placeId: Value(placeId),
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
    await _queue(tripId, 'expense', id);
  }

  /// Replaces an expense and its shares in one transaction.
  Future<void> updateExpense({
    required String id,
    required String title,
    required int amount,
    required String category,
    required String paidBy,
    required List<NewShare> shares,
    String splitMode = 'equally',
  }) async {
    assert(shares.fold<int>(0, (a, s) => a + s.share) == amount, 'shares must add up to amount');
    late String tripId;
    await _db.transaction(() async {
      final e = await (_db.select(_db.expenses)..where((x) => x.id.equals(id))).getSingle();
      tripId = e.tripId;
      await (_db.update(_db.expenses)..where((x) => x.id.equals(id))).write(ExpensesCompanion(
            title: Value(title),
            amount: Value(amount),
            category: Value(category),
            paidBy: Value(paidBy),
            splitMode: Value(splitMode),
            updatedAt: Value(DateTime.now()),
          ));
      await (_db.delete(_db.expenseShares)..where((s) => s.expenseId.equals(id))).go();
      for (final s in shares) {
        await _db.into(_db.expenseShares).insert(ExpenseSharesCompanion.insert(
              expenseId: id,
              tripId: e.tripId,
              memberId: s.memberId,
              share: s.share,
            ));
      }
    });
    await _queue(tripId, 'expense', id);
  }

  Future<Expense?> getExpense(String id) =>
      (_db.select(_db.expenses)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<List<ExpenseShare>> getShares(String expenseId) =>
      (_db.select(_db.expenseShares)..where((s) => s.expenseId.equals(expenseId))).get();

  Future<void> setBillPath(String expenseId, String? path) =>
      (_db.update(_db.expenses)..where((e) => e.id.equals(expenseId)))
          .write(ExpensesCompanion(billPath: Value(path)));

  /// Adds people to an existing trip. Existing expenses are not changed.
  Future<void> addMembers(String tripId, List<String> names) async {
    final existing = await (_db.select(_db.members)..where((m) => m.tripId.equals(tripId))).get();
    var i = existing.length;
    for (final n in names.where((n) => n.trim().isNotEmpty)) {
      if (existing.any((m) => m.name.toLowerCase() == n.trim().toLowerCase())) continue;
      final id = _uuid.v4();
      await _db.into(_db.members).insert(MembersCompanion.insert(
            id: id,
            tripId: tripId,
            name: n.trim(),
            colorIndex: Value(i++ % 6),
          ));
      await _queue(tripId, 'member', id);
    }
  }

  Future<void> setMemberUpi(String memberId, String upiId) async {
    await (_db.update(_db.members)..where((m) => m.id.equals(memberId))).write(MembersCompanion(upiId: Value(upiId)));
    final m = await (_db.select(_db.members)..where((x) => x.id.equals(memberId))).getSingleOrNull();
    if (m != null) await _queue(m.tripId, 'member', memberId);
  }

  /// Deletes an expense and its shares. Done explicitly instead of relying on
  /// SQLite's ON DELETE CASCADE, so balances can never keep orphaned shares.
  Future<void> deleteExpense(String id) async {
    final e = await getExpense(id);
    await _db.transaction(() async {
      await (_db.delete(_db.expenseShares)..where((s) => s.expenseId.equals(id))).go();
      await (_db.delete(_db.expenses)..where((x) => x.id.equals(id))).go();
    });
    if (e != null) await _queue(e.tripId, 'expense', id, op: 'delete');
  }

  /// Deletes a trip and everything in it.
  Future<void> deleteTrip(String tripId) => _db.transaction(() async {
        await (_db.delete(_db.expenseShares)..where((s) => s.tripId.equals(tripId))).go();
        await (_db.delete(_db.expenses)..where((e) => e.tripId.equals(tripId))).go();
        await (_db.delete(_db.settlements)..where((s) => s.tripId.equals(tripId))).go();
        await (_db.delete(_db.places)..where((p) => p.tripId.equals(tripId))).go();
        await (_db.delete(_db.members)..where((m) => m.tripId.equals(tripId))).go();
        await (_db.delete(_db.trips)..where((t) => t.id.equals(tripId))).go();
      });

  Future<void> addSettlement({
    required String tripId,
    required String fromMember,
    required String toMember,
    required int amount,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.settlements).insert(SettlementsCompanion.insert(
          id: id,
          tripId: tripId,
          fromMember: fromMember,
          toMember: toMember,
          amount: amount,
        ));
    await _queue(tripId, 'settlement', id);
  }

  // ---------- cloud sync support ----------

  /// Records a change for a shared trip, so the sync service can push it.
  Future<void> _queue(String tripId, String entity, String id, {String op = 'upsert'}) async {
    final t = await (_db.select(_db.trips)..where((x) => x.id.equals(tripId))).getSingleOrNull();
    if (t?.joinCode == null) return;
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(tripId: tripId, entity: entity, entityId: id, op: op));
  }

  Stream<List<OutboxData>> watchOutbox() =>
      (_db.select(_db.outbox)..orderBy([(o) => OrderingTerm.asc(o.seq)])).watch();

  Future<void> removeFromOutbox(int seq) => (_db.delete(_db.outbox)..where((o) => o.seq.equals(seq))).go();

  Stream<List<Trip>> watchSharedTrips() => (_db.select(_db.trips)..where((t) => t.joinCode.isNotNull())).watch();

  Future<Trip?> getTrip(String id) => (_db.select(_db.trips)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Member>> getMembers(String tripId) =>
      (_db.select(_db.members)..where((m) => m.tripId.equals(tripId))).get();

  /// Marks a trip as shared and links "me" to the signed-in account.
  Future<void> markShared(String tripId, String code, String uid) async {
    await (_db.update(_db.trips)..where((t) => t.id.equals(tripId))).write(TripsCompanion(joinCode: Value(code)));
    await (_db.update(_db.members)..where((m) => m.tripId.equals(tripId) & m.isMe.equals(true)))
        .write(MembersCompanion(uid: Value(uid)));
  }

  /// "This one is me" after joining someone else's trip.
  Future<void> claimMember(String tripId, String memberId, String uid) async {
    await (_db.update(_db.members)..where((m) => m.tripId.equals(tripId)))
        .write(const MembersCompanion(isMe: Value(false)));
    await (_db.update(_db.members)..where((m) => m.id.equals(memberId)))
        .write(MembersCompanion(isMe: const Value(true), uid: Value(uid)));
    await _queue(tripId, 'member', memberId);
  }

  /// Adds the joining person as a new member of a shared trip.
  Future<String> addMeToTrip(String tripId, String name, String uid, {String? upiId}) async {
    final count = (await getMembers(tripId)).length;
    final id = _uuid.v4();
    await (_db.update(_db.members)..where((m) => m.tripId.equals(tripId)))
        .write(const MembersCompanion(isMe: Value(false)));
    await _db.into(_db.members).insert(MembersCompanion.insert(
          id: id,
          tripId: tripId,
          name: name,
          isMe: const Value(true),
          uid: Value(uid),
          upiId: Value(upiId),
          colorIndex: Value(count % 6),
        ));
    await _queue(tripId, 'member', id);
    return id;
  }

  /// Whole-trip snapshot as plain maps, for the first upload.
  Future<Map<String, List<Map<String, Object?>>>> exportTrip(String tripId) async {
    final out = <String, List<Map<String, Object?>>>{'member': [], 'expense': [], 'settlement': [], 'place': []};
    for (final m in await getMembers(tripId)) {
      out['member']!.add((await exportEntity('member', m.id))!);
    }
    for (final e in await (_db.select(_db.expenses)..where((x) => x.tripId.equals(tripId))).get()) {
      out['expense']!.add((await exportEntity('expense', e.id))!);
    }
    for (final st in await (_db.select(_db.settlements)..where((x) => x.tripId.equals(tripId))).get()) {
      out['settlement']!.add((await exportEntity('settlement', st.id))!);
    }
    for (final p in await (_db.select(_db.places)..where((x) => x.tripId.equals(tripId))).get()) {
      out['place']!.add((await exportEntity('place', p.id))!);
    }
    return out;
  }

  Future<Map<String, Object?>?> exportTripDoc(String tripId) async {
    final t = await getTrip(tripId);
    if (t == null) return null;
    return {
      'name': t.name,
      'fromPlace': t.fromPlace,
      'toPlace': t.toPlace,
      'startDate': t.startDate?.millisecondsSinceEpoch,
      'endDate': t.endDate?.millisecondsSinceEpoch,
      'budget': t.budget,
      'cover': t.cover,
      'joinCode': t.joinCode,
      'updatedAt': t.updatedAt.millisecondsSinceEpoch,
    };
  }

  /// One row as a plain map (null if it no longer exists).
  Future<Map<String, Object?>?> exportEntity(String entity, String id) async {
    switch (entity) {
      case 'member':
        final m = await (_db.select(_db.members)..where((x) => x.id.equals(id))).getSingleOrNull();
        if (m == null) return null;
        return {'id': m.id, 'name': m.name, 'upiId': m.upiId, 'colorIndex': m.colorIndex, 'uid': m.uid};
      case 'expense':
        final e = await getExpense(id);
        if (e == null) return null;
        final shares = await getShares(id);
        return {
          'id': e.id,
          'title': e.title,
          'amount': e.amount,
          'category': e.category,
          'paidBy': e.paidBy,
          'splitMode': e.splitMode,
          'byVoice': e.byVoice,
          'note': e.note,
          'placeId': e.placeId,
          'spentAt': e.spentAt.millisecondsSinceEpoch,
          'updatedAt': e.updatedAt.millisecondsSinceEpoch,
          'shares': {for (final s in shares) s.memberId: s.share},
          'deleted': false,
        };
      case 'settlement':
        final s = await (_db.select(_db.settlements)..where((x) => x.id.equals(id))).getSingleOrNull();
        if (s == null) return null;
        return {
          'id': s.id,
          'fromMember': s.fromMember,
          'toMember': s.toMember,
          'amount': s.amount,
          'paidAt': s.paidAt.millisecondsSinceEpoch,
        };
      case 'place':
        final p = await (_db.select(_db.places)..where((x) => x.id.equals(id))).getSingleOrNull();
        if (p == null) return null;
        return {
          'id': p.id,
          'name': p.name,
          'type': p.type,
          'lat': p.lat,
          'lng': p.lng,
          'note': p.note,
          'visitedAt': p.visitedAt.millisecondsSinceEpoch,
        };
    }
    return null;
  }

  static DateTime? _ms(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
  static int _int(Object? v) => v is num ? v.toInt() : 0;

  /// Writes a trip that came from the cloud. Never queues anything.
  Future<void> applyRemoteTrip(String tripId, Map<String, Object?> d) async {
    final local = await getTrip(tripId);
    final updated = _ms(d['updatedAt']) ?? DateTime.now();
    if (local != null && local.updatedAt.isAfter(updated)) return;
    await _db.into(_db.trips).insertOnConflictUpdate(TripsCompanion(
          id: Value(tripId),
          name: Value(d['name'] as String? ?? 'Trip'),
          fromPlace: Value(d['fromPlace'] as String? ?? ''),
          toPlace: Value(d['toPlace'] as String? ?? ''),
          startDate: Value(_ms(d['startDate'])),
          endDate: Value(_ms(d['endDate'])),
          budget: Value(d['budget'] == null ? null : _int(d['budget'])),
          cover: Value(d['cover'] as String? ?? 'desert'),
          joinCode: Value(d['joinCode'] as String?),
          updatedAt: Value(updated),
        ));
  }

  /// Writes one row that came from the cloud. Never queues anything.
  Future<void> applyRemote(String tripId, String entity, String id, Map<String, Object?> d, {String? myUid}) async {
    switch (entity) {
      case 'member':
        final uid = d['uid'] as String?;
        await _db.into(_db.members).insertOnConflictUpdate(MembersCompanion(
              id: Value(id),
              tripId: Value(tripId),
              name: Value(d['name'] as String? ?? '?'),
              upiId: Value(d['upiId'] as String?),
              colorIndex: Value(_int(d['colorIndex'])),
              uid: Value(uid),
              isMe: Value(myUid != null && uid == myUid),
            ));
      case 'expense':
        final local = await getExpense(id);
        final updated = _ms(d['updatedAt']) ?? DateTime.now();
        if (d['deleted'] == true) {
          await _db.transaction(() async {
            await (_db.delete(_db.expenseShares)..where((s) => s.expenseId.equals(id))).go();
            await (_db.delete(_db.expenses)..where((x) => x.id.equals(id))).go();
          });
          return;
        }
        if (local != null && local.updatedAt.isAfter(updated)) return;
        final shares = (d['shares'] as Map?)?.map((k, v) => MapEntry(k as String, _int(v))) ?? const {};
        await _db.transaction(() async {
          await _db.into(_db.expenses).insertOnConflictUpdate(ExpensesCompanion(
                id: Value(id),
                tripId: Value(tripId),
                title: Value(d['title'] as String? ?? 'Expense'),
                amount: Value(_int(d['amount'])),
                category: Value(d['category'] as String? ?? 'other'),
                paidBy: Value(d['paidBy'] as String? ?? ''),
                splitMode: Value(d['splitMode'] as String? ?? 'equally'),
                byVoice: Value(d['byVoice'] == true),
                note: Value(d['note'] as String?),
                placeId: Value(d['placeId'] as String?),
                spentAt: Value(_ms(d['spentAt']) ?? updated),
                updatedAt: Value(updated),
              ));
          await (_db.delete(_db.expenseShares)..where((s) => s.expenseId.equals(id))).go();
          for (final e in shares.entries) {
            await _db.into(_db.expenseShares).insert(ExpenseSharesCompanion.insert(
                  expenseId: id,
                  tripId: tripId,
                  memberId: e.key,
                  share: e.value,
                ));
          }
        });
      case 'settlement':
        await _db.into(_db.settlements).insertOnConflictUpdate(SettlementsCompanion(
              id: Value(id),
              tripId: Value(tripId),
              fromMember: Value(d['fromMember'] as String? ?? ''),
              toMember: Value(d['toMember'] as String? ?? ''),
              amount: Value(_int(d['amount'])),
              paidAt: Value(_ms(d['paidAt']) ?? DateTime.now()),
            ));
      case 'place':
        await _db.into(_db.places).insertOnConflictUpdate(PlacesCompanion(
              id: Value(id),
              tripId: Value(tripId),
              name: Value(d['name'] as String? ?? 'Stop'),
              type: Value(d['type'] as String? ?? 'other'),
              lat: Value((d['lat'] as num?)?.toDouble()),
              lng: Value((d['lng'] as num?)?.toDouble()),
              note: Value(d['note'] as String?),
              visitedAt: Value(_ms(d['visitedAt']) ?? DateTime.now()),
            ));
    }
  }

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

    Future<String> place(String name, String type, double lat, double lng, int daysAgo, int hour) async {
      final id = _uuid.v4();
      final d = now.subtract(Duration(days: daysAgo));
      await _db.into(_db.places).insert(PlacesCompanion.insert(
            id: id,
            tripId: tripId,
            name: name,
            type: type,
            lat: Value(lat),
            lng: Value(lng),
            visitedAt: Value(DateTime(d.year, d.month, d.day, hour)),
          ));
      return id;
    }

    Future<void> add(String title, int rupees, String cat, String payer,
        {List<String>? only, int daysAgo = 0, bool voice = false, String? at}) {
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
        placeId: at,
        spentAt: now.subtract(Duration(days: daysAgo, hours: daysAgo == 0 ? 1 : 0)),
      );
    }

    await place('Left Indore', 'other', 22.7196, 75.8577, 1, 6);
    final dhaba = await place('Highway dhaba', 'snacks', 23.1000, 75.4000, 1, 8);
    final ratlam = await place('Petrol pump, Ratlam', 'fuel', 23.3315, 75.0367, 1, 10);
    final fort = await place('Chittorgarh Fort', 'tickets', 24.8887, 74.6269, 0, 11);
    final thali = await place('Shree Thal, Chittorgarh', 'food', 24.8790, 74.6290, 0, 13);
    final hotel = await place('Lake view hotel, Udaipur', 'stay', 24.5854, 73.7125, 0, 18);

    await add('Petrol', 2000, 'fuel', id('Neha'), daysAgo: 1, at: ratlam);
    await add('Chai and poha', 420, 'snacks', id('Priya'),
        only: [id('Priya'), id('Rahul'), id('Aman'), id('Neha'), id('You')], daysAgo: 1, voice: true, at: dhaba);
    await add('Petrol', 1500, 'fuel', id('Rahul'), voice: true, at: fort);
    await add('Toll plaza', 340, 'toll', id('Rahul'), voice: true);
    await add('Dal baati churma', 1860, 'food', id('Aman'), voice: true, at: thali);
    await add('Hotel, 2 rooms', 6400, 'stay', id('Vikas'), at: hotel);
    await add('Keychains', 100, 'shopping', id('Rahul'), only: [id('Rahul'), id('Aman')]);
    return tripId;
  }
}
