import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

const String _backendBaseUrl = 'https://your-backend.example.com';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important foreground notifications.',
    importance: Importance.max,
  );

  Future<void> initialize() async {
    await _initializeLocalNotifications();
    await _initializeFirebaseMessaging();
  }

  Future<void> _initializeFirebaseMessaging() async {
    await _requestPermissions();

    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final String? token = await _messaging.getToken();
    if (token != null) {
      debugPrint('FCM token: $token');
      await _sendTokenToBackend(token);
    } else {
      debugPrint('FCM token is null. Check notification permission / Firebase setup.');
    }

    _messaging.onTokenRefresh.listen((String refreshedToken) async {
      await _sendTokenToBackend(refreshedToken);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await showForegroundNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification tapped from background: ${message.messageId}');
    });

    final RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('Opened from terminated state: ${initialMessage.messageId}');
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      final NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('iOS permission status: ${settings.authorizationStatus}');
      return;
    }

    if (Platform.isAndroid) {
      // Needed for Android 13+ runtime notification permission.
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    }
  }

  String get _platformValue {
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isIOS) {
      return 'ios';
    }
    return 'unknown';
  }

  Future<void> _sendTokenToBackend(String token) async {
    if (_platformValue == 'unknown') {
      return;
    }

    if (_backendBaseUrl.contains('your-backend.example.com')) {
      debugPrint(
        'Skipping backend token sync because placeholder backend URL is still set.',
      );
      return;
    }

    final Uri uri = Uri.parse('$_backendBaseUrl/api/devices/register');
    final Map<String, dynamic> payload = <String, dynamic>{
      'deviceToken': token,
      'platform': _platformValue,
    };

    try {
      final http.Response response = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Token sync failed (${response.statusCode}): ${response.body}',
        );
      } else {
        debugPrint('Token synced to backend for $_platformValue');
      }
    } catch (e) {
      debugPrint('Error sending token to backend: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidInitSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosInitSettings =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: iosInitSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Local notification tapped: ${response.payload}');
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  Future<void> showForegroundNotification(RemoteMessage message) async {
    final RemoteNotification? notification = message.notification;
    final String title =
        notification?.title ?? message.data['title']?.toString() ?? 'Notification';
    final String body =
        notification?.body ?? message.data['body']?.toString() ?? '';

    final NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      message.messageId.hashCode,
      title,
      body,
      details,
      payload: jsonEncode(message.data),
    );
  }
}
