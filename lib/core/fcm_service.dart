import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

// Este handler TIENE que ser de nivel superior (top-level) para funcionar en background
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Inicializa servicios mínimos si fuesen necesarios en background.
  debugPrint("Handling a background message: ${message.messageId}");
}

class FCMService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // 1. Manejador para cuando la app está completamente cerrada o en segundo plano
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Pedir permisos en iOS y Android 13+
    await _requestPermissions();

    // 3. Configurar notificaciones locales para cuando la app está abierta en primer plano (foreground)
    await _setupLocalNotifications();

    // 4. Escuchar notificaciones en primer plano
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 5. Manejar clicks en notificaciones cuando la app está en background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("Notification clicked while in background!");
      // Aquí se podría navegar a la pantalla de chat o reservas dependiendo del payload
    });

    // 6. Si la app se abrió desde una notificación estando cerrada del todo (terminated)
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint("App opened from terminated state via notification");
      // Manejar la redirección
    }
  }

  static Future<String?> getToken() async {
    try {
      if (kIsWeb) {
        // En web se necesitaría el vapidKey, por ahora lo ignoramos
        return null;
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
      debugPrint('Local notification clicked: ${response.payload}');
    });

    // Crear canal de alta prioridad para Android
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'high_importance_channel', // id
        'High Importance Notifications', // title
        description: 'This channel is used for important notifications.', // description
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Got a message whilst in the foreground!');
    debugPrint('Message data: ${message.data}');

    // Si la notificación pertenece a un mensaje enviado por el propio usuario actual, no mostrar banner de eco
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null && message.data['senderId'] == currentUid) {
        debugPrint('Ignorando notificación en primer plano: proviene del propio usuario emisor.');
        return;
      }
    } catch (_) {}

    if (message.notification != null) {
      // Mostrar la notificación usando local_notifications
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
        payload: message.data.toString(), // Pasar los datos para usarlos al hacer click
      );
    }
  }
}
