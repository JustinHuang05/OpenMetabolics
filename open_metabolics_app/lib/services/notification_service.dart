import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;
  }

  /// Request notification permissions
  static Future<bool> requestPermissions() async {
    // Request permission for Android 13+
    if (await Permission.notification.isDenied) {
      final status = await Permission.notification.request();
      if (status.isDenied) {
        return false;
      }
    }

    // For iOS, permissions are requested during initialization
    return true;
  }

  /// Show a notification when session processing is complete
  static Future<void> showSessionCompleteNotification({
    required String sessionId,
    required int measurementCount,
  }) async {
    await initialize();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'session_complete',
      'Session Processing Complete',
      channelDescription:
          'Notifications for when session processing is complete',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      timeoutAfter: 5000, // 5 seconds
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _notifications.show(
      sessionId.hashCode, // Use session ID hash as notification ID
      'Session processing complete!',
      '', // Empty body
      platformChannelSpecifics,
      payload: sessionId, // Pass session ID as payload
    );
  }

  /// Show a notification when session processing fails
  static Future<void> showSessionErrorNotification({
    required String sessionId,
    required String errorMessage,
  }) async {
    await initialize();

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'session_error',
      'Session Processing Error',
      channelDescription: 'Notifications for when session processing fails',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      timeoutAfter: 5000, // 5 seconds
      styleInformation: BigTextStyleInformation(
        'There was an error processing your session: $errorMessage\n\nTap to view details or try again.',
        contentTitle: 'Session Processing Failed',
        htmlFormatBigText: true,
      ),
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _notifications.show(
      sessionId.hashCode +
          1000, // Use session ID hash + 1000 as notification ID for errors
      'Session Processing Failed',
      'There was an error processing your session: $errorMessage',
      platformChannelSpecifics,
      payload: 'error_$sessionId', // Pass error session ID as payload
    );
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      if (payload.startsWith('error_')) {
        // Handle error notification tap
        final sessionId = payload.substring(6); // Remove 'error_' prefix
        print('Error notification tapped for session: $sessionId');
        // You can navigate to an error page or show a dialog here
      } else {
        // Handle success notification tap
        print('Success notification tapped for session: $payload');
        // You can navigate to the session details page here
      }
    }
  }

  /// Cancel a specific notification
  static Future<void> cancelNotification(int notificationId) async {
    await _notifications.cancel(notificationId);
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
}
