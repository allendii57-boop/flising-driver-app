import "package:flutter_callkit_incoming/entities/entities.dart";
import "package:flutter_callkit_incoming/flutter_callkit_incoming.dart";
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message: ${message.notification?.title}');
  final callKitParams = CallKitParams(
    id: message.data['rideId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    nameCaller: 'New Ride Request',
    appName: 'Flising Driver',
    avatar: message.data['passengerPhoto'] ?? '',
    handle: message.data['pickupText'] ?? (message.notification?.body ?? 'Open app to accept'),
    type: 0,
    duration: 30000,
    textAccept: 'OPEN APP',
    textDecline: 'DISMISS',
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: 'Missed ride request',
    ),
    extra: message.data,
  );
  await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
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
    await FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app')
        .ref('drivers/${user.uid}/fcmToken')
        .set(token);
  }
