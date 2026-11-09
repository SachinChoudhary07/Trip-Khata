import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../db/app_database.dart';
import '../trips/data/trip_repository.dart';

/// Firebase settings come from --dart-define at build time (GitHub secrets in
/// CI). With no settings the app stays fully offline and hides cloud features.
class CloudConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static bool get present => apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Offline-first sync. The phone's database stays the source of truth:
/// - local edits to a shared trip go into the outbox and are pushed to Firestore
///   (Firestore queues them itself while offline);
/// - Firestore listeners write remote edits back into the local database.
///
/// Firestore layout: trips/{tripId} with members, expenses, settlements and
/// places as subcollections. Expenses carry their shares and a `deleted` flag.
class CloudSync extends ChangeNotifier {
  CloudSync(this._repo);
  final TripRepository _repo;

  bool _available = false;
  bool get available => _available;
  User? get user => _available ? FirebaseAuth.instance.currentUser : null;

  StreamSubscription<List<OutboxData>>? _outboxSub;
  StreamSubscription<List<Trip>>? _sharedSub;
  StreamSubscription<User?>? _authSub;
  final Map<String, List<StreamSubscription<Object?>>> _tripSubs = {};
  bool _pushing = false;

  static const _subcollections = {'member': 'members', 'expense': 'expenses', 'settlement': 'settlements', 'place': 'places'};

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> _tripDoc(String id) => _fs.collection('trips').doc(id);

  Future<void> init() async {
    if (!CloudConfig.present) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: CloudConfig.apiKey,
          appId: CloudConfig.appId,
          projectId: CloudConfig.projectId,
          messagingSenderId: CloudConfig.senderId,
        ),
      );
      await GoogleSignIn.instance.initialize(
        serverClientId: CloudConfig.webClientId.isEmpty ? null : CloudConfig.webClientId,
      );
      _available = true;
      _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
        notifyListeners();
        u == null ? _stopSync() : _startSync();
      });
    } catch (e) {
      debugPrint('Cloud disabled: $e');
      _available = false;
    }
    notifyListeners();
  }

  // ---------- auth ----------

  Future<User> signInWithGoogle() async {
    if (!_available) throw SyncException('Cloud sync is not set up in this build.');
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw SyncException('Google did not return a sign-in token.');
    final cred = await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    notifyListeners();
    return cred.user!;
  }

  Future<void> signOut() async {
    if (!_available) return;
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
    notifyListeners();
  }

  // ---------- share & join ----------

  static String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Uploads a trip and returns its join code. Safe to call again.
  Future<String> shareTrip(String tripId) async {
    final u = user ?? await signInWithGoogle();
    final trip = await _repo.getTrip(tripId);
    if (trip == null) throw SyncException('Trip not found.');
    final code = trip.joinCode ?? _newCode();
    await _repo.markShared(tripId, code, u.uid);

    final doc = (await _repo.exportTripDoc(tripId))!;
    final batch = _fs.batch();
    batch.set(
      _tripDoc(tripId),
      {...doc, 'ownerUid': u.uid, 'memberUids': FieldValue.arrayUnion([u.uid])},
      SetOptions(merge: true),
    );
    final rows = await _repo.exportTrip(tripId);
    for (final e in rows.entries) {
      for (final row in e.value) {
        batch.set(_tripDoc(tripId).collection(_subcollections[e.key]!).doc(row['id'] as String), row);
      }
    }
    unawaited(batch.commit());
    _listenTrip(tripId);
    return code;
  }

  /// Joins a shared trip by code. Returns the local trip id.
  Future<String> joinTrip(String rawCode) async {
    final code = rawCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final u = user ?? await signInWithGoogle();
    final q = await _fs.collection('trips').where('joinCode', isEqualTo: code).limit(1).get();
    if (q.docs.isEmpty) throw SyncException('No trip found for code $code.');
    final doc = q.docs.first;
    await doc.reference.update({'memberUids': FieldValue.arrayUnion([u.uid])});
    await _repo.applyRemoteTrip(doc.id, doc.data());
    for (final e in _subcollections.entries) {
      final snap = await doc.reference.collection(e.value).get();
      for (final d in snap.docs) {
        await _repo.applyRemote(doc.id, e.key, d.id, d.data(), myUid: u.uid);
      }
    }
    _listenTrip(doc.id);
    return doc.id;
  }

  // ---------- background sync ----------

  void _startSync() {
    _outboxSub ??= _repo.watchOutbox().listen((rows) => _push(rows));
    _sharedSub ??= _repo.watchSharedTrips().listen((trips) {
      for (final t in trips) {
        _listenTrip(t.id);
      }
    });
  }

  void _stopSync() {
    _outboxSub?.cancel();
    _outboxSub = null;
    _sharedSub?.cancel();
    _sharedSub = null;
    for (final subs in _tripSubs.values) {
      for (final s in subs) {
        s.cancel();
      }
    }
    _tripSubs.clear();
  }

  Future<void> _push(List<OutboxData> rows) async {
    if (_pushing || rows.isEmpty || user == null) return;
    _pushing = true;
    try {
      final batch = _fs.batch();
      for (final r in rows.take(400)) {
        final ref = _tripDoc(r.tripId).collection(_subcollections[r.entity]!).doc(r.entityId);
        final data = r.op == 'delete' ? null : await _repo.exportEntity(r.entity, r.entityId);
        if (data == null) {
          if (r.entity == 'expense') {
            batch.set(ref, {'deleted': true, 'updatedAt': DateTime.now().millisecondsSinceEpoch}, SetOptions(merge: true));
          } else {
            batch.delete(ref);
          }
        } else {
          batch.set(ref, data);
        }
      }
      // Firestore keeps the batch in its own offline queue, so the outbox
      // rows can go now; the commit completes whenever the network is back.
      unawaited(batch.commit().catchError((Object e) => debugPrint('Sync push failed: $e')));
      for (final r in rows.take(400)) {
        await _repo.removeFromOutbox(r.seq);
      }
    } finally {
      _pushing = false;
    }
  }

  void _listenTrip(String tripId) {
    if (_tripSubs.containsKey(tripId) || user == null) return;
    final uid = user!.uid;
    final subs = <StreamSubscription<Object?>>[
      _tripDoc(tripId).snapshots().listen((s) {
        final d = s.data();
        if (d != null) _repo.applyRemoteTrip(tripId, d);
      }, onError: (Object e) => debugPrint('Trip listen error: $e')),
    ];
    for (final e in _subcollections.entries) {
      subs.add(_tripDoc(tripId).collection(e.value).snapshots().listen((snap) async {
        for (final c in snap.docChanges) {
          if (c.type == DocumentChangeType.removed) continue;
          final d = c.doc.data();
          if (d != null) await _repo.applyRemote(tripId, e.key, c.doc.id, d, myUid: uid);
        }
      }, onError: (Object err) => debugPrint('Sync listen error: $err')));
    }
    _tripSubs[tripId] = subs;
  }

  @override
  void dispose() {
    _stopSync();
    _authSub?.cancel();
    super.dispose();
  }
}
