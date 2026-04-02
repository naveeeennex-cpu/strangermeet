import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Top-level background message handler — MUST be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by this point (Flutter ensures it).
  // We just log; flutter_local_notifications shows the system notification.
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'stranger_meet_default',
    'StrangerMeet Notifications',
    description: 'Chat messages, friend requests, and event updates',
    importance: Importance.high,
    playSound: true,
  );

  /// Call once from main() after Firebase.initializeApp().
  Future<void> init() async {
    // 1. Request permission (iOS + Android 13+)
    await _requestPermission();

    // 2. Create Android notification channel
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // 3. Initialise flutter_local_notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 4. Register background handler (must call before FirebaseMessaging.onMessage)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 5. Foreground message handler — show heads-up notification manually
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 6. Register / refresh FCM token with our backend
    await _registerToken();

    // Listen for token refreshes
    _messaging.onTokenRefresh.listen((newToken) => _sendTokenToServer(newToken));
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
  }

  Future<void> _registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('[FCM] Token: $token');
        await _sendTokenToServer(token);
      }
    } catch (e) {
      debugPrint('[FCM] Token fetch error: $e');
    }
  }

  Future<void> _sendTokenToServer(String token) async {
    try {
      final api = ApiService();
      await api.post('/users/fcm-token', data: {'token': token});
    } catch (e) {
      debugPrint('[FCM] Failed to send token to server: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final android = notification.android;
    _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: android?.smallIcon ?? '@mipmap/ic_launcher',
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['type'],
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    // Navigation on tap is handled by app's notification open handler
    debugPrint('[FCM] Notification tapped: ${response.payload}');
  }

  /// Call this when the user explicitly logs out to clear the FCM token.
  Future<void> clearToken() async {
    try {
      await _messaging.deleteToken();
      final api = ApiService();
      await api.post('/users/fcm-token', data: {'token': ''});
    } catch (_) {}
  }
}
