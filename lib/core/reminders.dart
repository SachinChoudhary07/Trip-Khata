import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notifications: the daily 9 PM nudge, and trip activity (a friend
/// added an expense) raised by the sync service while the app is open.
/// Push messages from the Cloud Function use the same channel and the same
/// tag (the trip id), so a push and a local notice for one trip replace each
/// other instead of stacking up.
class Reminders {
  Reminders._();
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _id = 21;

  /// Called with a trip id when the user taps an activity notification.
  static void Function(String tripId)? onOpenTrip;
  static String? _pendingTrip;

  static const activityChannel = 'trip_activity';
  static const _activityChannel = AndroidNotificationChannel(
    activityChannel,
    'Trip activity',
    description: 'When friends add or change expenses in a shared trip',
    importance: Importance.high,
  );

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      // The app is built for India; IST has no daylight saving.
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
      // Create the channel up front so pushes that arrive before any local
      // notice still land in it.
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_activityChannel);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) _pendingTrip = launch!.notificationResponse?.payload;
      _ready = true;
    } catch (e) {
      debugPrint('Reminders init failed: $e');
    }
  }

  /// Opens a trip from a tapped notification (local or push).
  static void open(String? tripId) => _open(tripId);

  static void _open(String? tripId) {
    if (tripId == null || tripId.isEmpty) return;
    final cb = onOpenTrip;
    cb == null ? _pendingTrip = tripId : cb(tripId);
  }

  /// Trip to open if the app was launched by tapping a notification.
  static String? takeLaunchTrip() {
    final t = _pendingTrip;
    _pendingTrip = null;
    return t;
  }

  static Future<void> requestPermission() async {
    await init();
    if (!_ready) return;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// One notification per trip (a new one replaces the previous for that trip).
  static Future<void> showActivity({required String tripId, required String title, required String body}) async {
    await init();
    if (!_ready) return;
    await _plugin.show(
      0,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _activityChannel.id,
          _activityChannel.name,
          channelDescription: _activityChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          tag: tripId,
        ),
      ),
      payload: tripId,
    );
  }

  /// Budget alerts: their own channel, one notification per trip.
  static Future<void> showBudget({required String tripId, required String title, required String body}) async {
    await init();
    if (!_ready) return;
    await _plugin.show(
      1,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'trip_budget',
          'Budget alerts',
          channelDescription: 'When a trip reaches 80% and 100% of its budget',
          importance: Importance.high,
          priority: Priority.high,
          tag: 'budget-$tripId',
        ),
      ),
      payload: tripId,
    );
  }

  static Future<void> setEnabled(bool on) async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(_id);
    if (!on) return;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, 21);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      _id,
      'Add today’s expenses',
      'Takes 10 seconds. Tap the mic and just say it.',
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Daily reminder',
          channelDescription: 'A nudge at 9 PM to log the day’s spends',
          importance: Importance.defaultImportance,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
