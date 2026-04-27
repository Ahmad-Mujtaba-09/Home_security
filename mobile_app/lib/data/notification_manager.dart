import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/constants.dart';
import 'models.dart';

/// Manages local notifications with per-event-type throttling.
///
/// The same `event_type` will only trigger a notification once every
/// [AppConstants.notificationThrottleSecs] seconds to prevent spam from
/// high-frequency frame logs.
class NotificationManager {
  NotificationManager._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Tracks the last notification time for each event_type.
  static final Map<String, DateTime> _lastNotified = {};

  static int _nextId = 0;

  /// Initialise the local notifications plugin.
  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);

    // Request permission on Android 13+
    if (!kIsWeb && Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  /// Show a notification for the given [event], throttled by event_type.
  ///
  /// Returns `true` if the notification was shown, `false` if throttled.
  static bool notify(HistoryEvent event) {
    final now = DateTime.now();
    final lastTime = _lastNotified[event.eventType];

    if (lastTime != null &&
        now.difference(lastTime).inSeconds <
            AppConstants.notificationThrottleSecs) {
      // Throttled — skip this notification
      debugPrint(
        'Notification throttled for ${event.eventType} '
        '(last sent ${now.difference(lastTime).inSeconds}s ago)',
      );
      return false;
    }

    // Update the last-notified timestamp
    _lastNotified[event.eventType] = now;

    _show(event);
    return true;
  }

  static Future<void> _show(HistoryEvent event) async {
    const androidDetails = AndroidNotificationDetails(
      'safeguard_alerts',
      'Safety Alerts',
      channelDescription: 'Real-time safety event notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      _nextId++,
      event.displayLabel,
      event.notificationBody,
      details,
    );
  }

  /// Clear the throttle cache (e.g. on sign-out).
  static void reset() {
    _lastNotified.clear();
    _nextId = 0;
  }
}
