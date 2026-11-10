import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../core/reminders.dart';

/// Firebase Cloud Messaging. The phone registers its push token under
/// `tripkhata_users/{uid}`; the `tripkhataExpenseNotify` Cloud Function reads
/// it and pushes "Rahul added ₹1,500" to everyone else in the trip, even when
/// their app is closed.
class PushService {
  PushService._();

  static const usersCollection = 'tripkhata_users';

  static String? _token;
  static String? _uid;
  static StreamSubscription<String>? _refreshSub;

  /// True once this phone has a push token stored for the signed-in user.
  static bool get active => _token != null && _uid != null;

  /// Taps on push notifications open the trip. Call once after Firebase is up.
  static Future<void> init() async {
    try {
      FirebaseMessaging.onMessageOpenedApp.listen((m) => Reminders.open(m.data['tripId'] as String?));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) Reminders.open(initial.data['tripId'] as String?);
    } catch (e) {
      debugPrint('Push init failed: $e');
    }
  }

  static DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      FirebaseFirestore.instance.collection(usersCollection).doc(uid);

  /// Stores this phone's token for [uid] and keeps it fresh.
  static Future<void> register(String uid, {required bool notify}) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _uid = uid;
      _token = token;
      await _save(uid, token, notify: notify);
      await _refreshSub?.cancel();
      _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        final old = _token;
        _token = t;
        final u = _uid;
        if (u == null) return;
        await _save(u, t, notify: null);
        if (old != null && old != t) {
          await _doc(u).set({'tokens': FieldValue.arrayRemove([old])}, SetOptions(merge: true));
        }
      });
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  static Future<void> _save(String uid, String token, {required bool? notify}) => _doc(uid).set({
        'tokens': FieldValue.arrayUnion([token]),
        if (notify != null) 'notify': notify,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));

  /// The Settings switch: the Cloud Function skips users with notify == false.
  static Future<void> setNotify(bool on) async {
    final u = _uid;
    if (u == null) return;
    try {
      await _doc(u).set({'notify': on}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Push setNotify failed: $e');
    }
  }

  /// On sign-out this phone stops getting that account's pushes.
  static Future<void> unregister() async {
    final u = _uid;
    final t = _token;
    _uid = null;
    _token = null;
    await _refreshSub?.cancel();
    _refreshSub = null;
    if (u == null || t == null) return;
    try {
      await _doc(u).set({'tokens': FieldValue.arrayRemove([t])}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Push unregister failed: $e');
    }
  }
}
