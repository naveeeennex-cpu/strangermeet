import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import '../config/router.dart';

/// Top-level background message handler — MUST be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  /// Set this to the user ID of the person you're currently chatting with.
  /// When set, foreground notifications from this sender are suppressed.
  String? activeChatUserId;

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

    // 6. Handle notification taps when app was in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 7. Handle notification tap that launched the app from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // Delay slightly to ensure router is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateFromMessage(initialMessage.data);
      });
    }

    // 8. Register / refresh FCM token with our backend
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

    // Suppress notification if user is already on the chat screen with this sender
    final msgType = message.data['type']?.toString();
    final senderId = message.data['sender_id']?.toString();
    if (msgType == 'new_message' &&
        senderId != null &&
        senderId == activeChatUserId) {
      debugPrint('[FCM] Suppressed notification — already chatting with $senderId');
      return;
    }

    final android = notification.android;

    // Encode the full data map as JSON payload so tap handler can navigate
    final payload = jsonEncode(message.data);

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
      payload: payload,
    );
  }

  /// Called when user taps a local notification (foreground-shown).
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('[FCM] Notification tapped: ${response.payload}');
    if (response.payload == null || response.payload!.isEmpty) return;

    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _navigateFromMessage(data);
    } catch (e) {
      debugPrint('[FCM] Failed to parse notification payload: $e');
    }
  }

  /// Called when user taps a system notification while app was in background.
  void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Message opened app: ${message.data}');
    _navigateFromMessage(message.data);
  }

  /// Central navigation handler for all notification taps.
  void _navigateFromMessage(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';

    switch (type) {
      case 'new_message':
        // Navigate to chat with the sender
        final senderId = data['sender_id']?.toString();
        final senderName = data['sender_name']?.toString() ?? 'Chat';
        if (senderId != null && senderId.isNotEmpty) {
          router.push('/chat/$senderId?name=${Uri.encodeComponent(senderName)}');
        }
        break;

      case 'friend_request':
        // Navigate to friend requests screen
        router.push('/friend-requests');
        break;

      case 'event_update':
        // Navigate to event detail
        final communityId = data['community_id']?.toString();
        final eventId = data['event_id']?.toString();
        if (communityId != null && eventId != null) {
          router.push('/community/$communityId/event/$eventId');
        }
        break;

      default:
        // Unknown type — go to notifications screen
        router.push('/notifications');
        break;
    }
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
