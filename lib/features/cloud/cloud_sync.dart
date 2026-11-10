import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/reminders.dart';
import '../../core/utils/money.dart';
import '../../db/app_database.dart';
import '../trips/data/trip_repository.dart';
import 'push_service.dart';

/// Firebase settings for the `com.trip_khata.trip_khata` Android app in the
/// flutter-apps-975a6 project (from google-services.json; these values are
/// public identifiers, not secrets). Can be overridden with --dart-define.
class CloudConfig {
  static const apiKey =
      String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyAIWXDrxrfjsvXHdbnGIa3wVWemBgHRiWE');
  static const appId =
      String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:587001182182:android:1fcfa4c2af921ff42d4827');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'flutter-apps-975a6');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '587001182182');
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID',
      defaultValue: '587001182182-61s04ehq1d0ceo48qe4lko57jd9up027.apps.googleusercontent.com');

  /// The Firebase project is shared with other apps, so TripKhata keeps all
  /// its data under its own top-level collection.
  static const tripsCollection = 'tripkhata_trips';

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
/// Firestore layout: tripkhata_trips/{tripId} with members, expenses, settlements and
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
  DocumentReference<Map<String, dynamic>> _tripDoc(String id) => _fs.collection(CloudConfig.tripsCollection).doc(id);

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
      unawaited(PushService.init());
      _authSub = FirebaseAuth.instance.authStateChanges().listen((u) async {
        notifyListeners();
        if (u == null) {
          _stopSync();
          return;
        }
        _startSync();
        final profile = await _repo.getProfile();
        unawaited(PushService.register(u.uid, notify: profile?.notifyActivity ?? true));
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
    await PushService.unregister();
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
    unawaited(Reminders.requestPermission());
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
    unawaited(Reminders.requestPermission());
    final q = await _fs.collection(CloudConfig.tripsCollection).where('joinCode', isEqualTo: code).limit(1).get();
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
    await _repo.setActiveTrip(doc.id); // the trip you just joined is the one you'll add to
    return doc.id;
  }

  /// True when the signed-in user created this shared trip. Null if unknown (offline).
  Future<bool?> isOwner(String tripId) async {
    if (user == null) return null;
    try {
      final d = await _tripDoc(tripId).get();
      return d.data()?['ownerUid'] == user!.uid;
    } catch (_) {
      return null;
    }
  }

  void _stopTrip(String tripId) {
    for (final s in _tripSubs.remove(tripId) ?? const <StreamSubscription<Object?>>[]) {
      s.cancel();
    }
  }

  /// Leave a shared trip: you stop syncing and it is removed from this phone.
  /// Everyone else keeps the trip and its history.
  Future<void> leaveTrip(String tripId) async {
    _stopTrip(tripId);
    final u = user;
    if (_available && u != null) {
      unawaited(_tripDoc(tripId)
          .update({'memberUids': FieldValue.arrayRemove([u.uid])})
          .catchError((Object e) => debugPrint('Leave failed: $e')));
    }
    await _repo.deleteTrip(tripId);
  }

  /// Owner only: delete the shared trip for everyone, then from this phone.
  Future<void> deleteForEveryone(String tripId) async {
    _stopTrip(tripId);
    if (_available && user != null) {
      final ref = _tripDoc(tripId);
      for (final sub in _subcollections.values) {
        try {
          final snap = await ref.collection(sub).get();
          final batch = _fs.batch();
          for (final d in snap.docs) {
            batch.delete(d.reference);
          }
          unawaited(batch.commit().catchError((Object e) => debugPrint('Delete failed: $e')));
        } catch (e) {
          debugPrint('Delete failed: $e');
        }
      }
      unawaited(ref.delete().catchError((Object e) => debugPrint('Delete failed: $e')));
    }
    await _repo.deleteTrip(tripId);
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
        if (r.entity == 'trip') {
          final doc = await _repo.exportTripDoc(r.tripId);
          if (doc != null) batch.set(_tripDoc(r.tripId), doc, SetOptions(merge: true));
          continue;
        }
        final ref = _tripDoc(r.tripId).collection(_subcollections[r.entity]!).doc(r.entityId);
        final data = r.op == 'delete' ? null : await _repo.exportEntity(r.entity, r.entityId);
        if (data == null) {
          if (r.entity == 'expense') {
            batch.set(
              ref,
              {'deleted': true, 'updatedAt': DateTime.now().millisecondsSinceEpoch, 'editedBy': user!.uid},
              SetOptions(merge: true),
            );
          } else {
            batch.delete(ref);
          }
        } else {
          batch.set(ref, r.entity == 'expense' ? {...data, 'editedBy': user!.uid} : data);
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
      var firstSnapshot = true;
      subs.add(_tripDoc(tripId).collection(e.value).snapshots().listen((snap) async {
        final catchUp = firstSnapshot;
        firstSnapshot = false;
        final activity = <_Activity>[];
        for (final c in snap.docChanges) {
          if (c.type == DocumentChangeType.removed) continue;
          final d = c.doc.data();
          if (d == null) continue;
          if (e.key == 'expense') {
            final before = await _repo.getExpense(c.doc.id);
            final by = d['editedBy'] as String?;
            final fromOther = by != null && by != uid && !c.doc.metadata.hasPendingWrites;
            final remoteUpdated = d['updatedAt'] is int ? d['updatedAt'] as int : 0;
            final isNewer = before == null || before.updatedAt.millisecondsSinceEpoch < remoteUpdated;
            if (fromOther && isNewer) {
              final deleted = d['deleted'] == true;
              if (!(deleted && before == null)) {
                activity.add(_Activity(
                  by: by,
                  kind: deleted ? 'deleted' : (before == null ? 'added' : 'edited'),
                  title: (d['title'] as String?) ?? before?.title ?? 'an expense',
                  amount: d['amount'] is num ? (d['amount'] as num).toInt() : (before?.amount ?? 0),
                  shares: (d['shares'] as Map?)?.map((k, v) => MapEntry(k as String, (v as num).toInt())) ?? const {},
                ));
              }
            }
          }
          await _repo.applyRemote(tripId, e.key, c.doc.id, d, myUid: uid);
        }
        if (activity.isNotEmpty && _shouldNotifyLocally(catchUp)) await _notify(tripId, activity, uid);
      }, onError: (Object err) => debugPrint('Sync listen error: $err')));
    }
    _tripSubs[tripId] = subs;
  }

  /// With push working, the Cloud Function covers the background and closed
  /// app, so local notices are only for changes that arrive while the app is
  /// on screen (Android doesn't show pushes for a foreground app). Without
  /// push (function not deployed, no Play services) local notices cover
  /// everything, including what arrived while the app was closed.
  bool _shouldNotifyLocally(bool catchUp) {
    if (!PushService.active) return true;
    if (catchUp) return false;
    return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  /// "Rahul added ₹1,500 · Petrol", or a summary when several arrive at once.
  Future<void> _notify(String tripId, List<_Activity> items, String myUid) async {
    final profile = await _repo.getProfile();
    if (profile != null && !profile.notifyActivity) return;
    final trip = await _repo.getTrip(tripId);
    final members = await _repo.getMembers(tripId);
    String who(String uid) => members.where((m) => m.uid == uid).firstOrNull?.name ?? 'Someone';
    final me = members.where((m) => m.uid == myUid).firstOrNull;
    final tripName = trip?.name ?? 'your trip';

    if (items.length == 1) {
      final a = items.single;
      final myShare = me == null ? null : a.shares[me.id];
      final title = switch (a.kind) {
        'added' => '${who(a.by)} added ${formatPaise(a.amount)}',
        'edited' => '${who(a.by)} edited ${a.title}',
        _ => '${who(a.by)} deleted ${a.title}',
      };
      final body = [
        if (a.kind != 'deleted') a.title,
        tripName,
        if (a.kind != 'deleted') myShare == null || myShare == 0 ? 'not in your share' : 'your share ${formatPaise(myShare)}',
      ].join(' · ');
      await Reminders.showActivity(tripId: tripId, title: title, body: body);
      return;
    }
    final names = items.map((a) => who(a.by)).toSet().toList();
    final added = items.where((a) => a.kind == 'added');
    final total = added.fold<int>(0, (s, a) => s + a.amount);
    final people = names.length == 1 ? names.first : '${names.first} and ${names.length - 1} other${names.length > 2 ? 's' : ''}';
    await Reminders.showActivity(
      tripId: tripId,
      title: '${items.length} updates in $tripName',
      body: added.isEmpty ? '$people changed expenses' : '$people added ${formatPaise(total)} in total',
    );
  }

  @override
  void dispose() {
    _stopSync();
    _authSub?.cancel();
    super.dispose();
  }
}

class _Activity {
  const _Activity({required this.by, required this.kind, required this.title, required this.amount, required this.shares});
  final String by;
  final String kind;
  final String title;
  final int amount;
  final Map<String, int> shares;
}
