import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripkhata/db/app_database.dart';

void main() {
  test('upgrading re-runs safely when tables already have the new columns', () async {
    final dir = await Directory.systemTemp.createTemp('tk_mig');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    // A database with today's schema that claims to be version 1, like a
    // phone where profiles was created with all its columns during an upgrade.
    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.profiles).insert(ProfilesCompanion.insert(name: 'Sachin'));
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final p = await (db.select(db.profiles)).getSingle(); // runs onUpgrade 1 -> 7
    expect(p.name, 'Sachin');
    expect(p.notifyBudget, isTrue);
    await db.close();
  });
}
