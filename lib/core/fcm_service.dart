import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:senicare/core/globals.dart';

// Este handler TIENE que ser de nivel superior (top-level) para funcionar en background
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

class FCMService {
  static FirebaseMessaging get _firebaseMessaging => FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (!useFirebaseBackend || Firebase.apps.isEmpty) {
      return;
    }
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }

    await _requestPermissions();
    if (!kIsWeb) {
      await _setupLocalNotifications();
    }

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _dispatchNotificationRoute(message.data);
    });

    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _dispatchNotificationRoute(initialMessage.data);
    }
  }

  static void _dispatchNotificationRoute(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    final normalized = <String, dynamic>{};
    data.forEach((key, value) {
      normalized[key] = value;
    });
    final bookingId = normalized['bookingId']?.toString().trim();
    if (bookingId != null && bookingId.isNotEmpty) {
      pendingTrackingBookingId.value = bookingId;
    }
    pendingPushRoute.value = normalized;
  }

  static void _handleRawPayloadClick(String? payload) {
    if (payload == null || payload.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _dispatchNotificationRoute(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      debugPrint('Could not parse notification payload: $e');
    }
  }

  static Future<String?> getToken() async {
    try {
      if (!useFirebaseBackend || Firebase.apps.isEmpty) {
        return null;
      }
      if (kIsWeb) {
        const defineVapid = String.fromEnvironment('FCM_WEB_VAPID_KEY');
        final envVapid = dotenv.isInitialized ? dotenv.env['FCM_WEB_VAPID_KEY'] : null;
        final vapidKey = defineVapid.isNotEmpty ? defineVapid : (envVapid ?? '');
        if (vapidKey.isEmpty) return null;
        return await _firebaseMessaging.getToken(vapidKey: vapidKey);
      }
      return await _firebaseMessaging.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  static Future<void> _requestPermissions() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('User granted permission: ${settings.authorizationStatus}');
  }

  static Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handleRawPayloadClick(response.payload);
      },
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      const channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Got a message whilst in the foreground: ${message.data}');

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null && message.data['senderId'] == currentUid) {
        return;
      }
    } catch (_) {}

    if (kIsWeb) return;

    if (message.notification != null) {
      _localNotifications.show(
        id: message.hashCode,
        title: message.notification!.title,
        body: message.notification!.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            channelDescription: 'This channel is used for important notifications.',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }
}
