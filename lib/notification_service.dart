import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message: ${message.notification?.title}');
}

class NotificationService {
  static final _fcm = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await saveToken();
    _fcm.onTokenRefresh.listen((_) => saveToken());
    FirebaseMessaging.onMessage.listen((message) {
      print('Foreground: ${message.notification?.title}');
    });
    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler
    );
  }

  static Future<void> saveToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await _fcm.getToken();
    if (token == null) return;
    await FirebaseDatabase.instance
        .ref('drivers/${user.uid}/fcmToken')
        .set(token);
  }
}
