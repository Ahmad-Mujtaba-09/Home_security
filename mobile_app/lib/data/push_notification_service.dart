import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_manager.dart';
import 'models.dart';

/// Handles background FCM messages (must be top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background notifications are shown automatically by the system tray.
  debugPrint('FCM background message: ${message.messageId}');
}

/// Manages Firebase Cloud Messaging for push notifications.
class PushNotificationService {
  PushNotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _listenersRegistered = false;

  /// Initialize FCM: request permission and set up foreground listener.
  /// Call this early in main() — it does NOT save the token yet.
  static Future<void> init() async {
    // Request notification permission (Android 13+ / iOS)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    // Set up foreground message listener (only once)
    if (!_listenersRegistered) {
      _listenersRegistered = true;

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM foreground message: ${message.notification?.title}');
        if (message.notification != null) {
          final event = HistoryEvent(
            id: message.messageId ?? '',
            userId: '',
            eventType: message.data['event_type'] ??
                message.notification!.title ??
                'Alert',
            confidence:
                double.tryParse(message.data['confidence'] ?? '') ?? 0.0,
            timestamp: DateTime.now(),
          );
          NotificationManager.notify(event);
        }
      });
    }
  }

  /// Register/save the FCM token to Supabase.
  /// Call this AFTER the user has logged in so userId is available.
  static Future<void> registerToken() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('FCM registerToken skipped — no user logged in');
        return;
      }

      final token = await _messaging.getToken();
      debugPrint('FCM token: $token');
      if (token != null) {
        await _saveToken(token);
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen(_saveToken);
    } catch (e) {
      debugPrint('FCM registerToken error: $e');
    }
  }

  /// Save FCM token to the Supabase `fcm_tokens` table.
  static Future<void> _saveToken(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client.from('fcm_tokens').upsert({
        'user_id': userId,
        'token': token,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      debugPrint('FCM token saved to Supabase for user $userId');
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }
}
