import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // Initialize timezone package
    tz.initializeTimeZones();

    // Android initialization settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification clicked: ${response.payload}');
      },
    );

    await requestPermissions();
  }

  // Request notification permissions (required for Android 13+)
  Future<void> requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Request exact alarm permission for Android 12+
    final plugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (plugin != null) {
      await plugin.requestNotificationsPermission();
      await plugin.requestExactAlarmsPermission();
    }
  }

  // Send instant notification for band wear reminder
  Future<void> showBandWearNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'wear_band_channel',
          'Band Notifications',
          channelDescription: 'Reminder to wear your health band',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      101, // Unique ID for this notification
      'Band Reminder',
      'Please wear your band',
      details,
      payload: 'wear_band',
    );
  }

  // Schedule notification after specified seconds
  Future<void> scheduleNotification(
    int id,
    String title,
    String body,
    int seconds,
  ) async {
    final scheduledTime = tz.TZDateTime.now(
      tz.local,
    ).add(Duration(seconds: seconds));

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'scheduled_channel',
          'Scheduled Notifications',
          channelDescription: 'Channel for scheduled notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
