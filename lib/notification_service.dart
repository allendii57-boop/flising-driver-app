import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Convert any Firebase rideId into a deterministic valid UUID v4 format for Android CallKit
String rideIdToUuid(String input) {
  final hex = input.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join().padRight(32, '0').substring(0, 32);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}-a${hex.substring(17, 20)}-${hex.substring(20, 32)}';
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  final String type = message.data['type']?.toString() ?? '';
  final String rideId = message.data['rideId']?.toString() ?? 'default_ride';
  final String callUuid = rideIdToUuid(rideId);

  if (type == 'RIDE_CANCELLED') {
    await FlutterCallkitIncoming.endCall(callUuid);
    await FlutterCallkitIncoming.endAllCalls();
    return;
  }

  if (type != 'NEW_RIDE' && message.notification != null) {
    return;
  }

  final String pickup = message.data['pickupText']?.toString() ?? 'New Ride Request';
  final String dropoff = message.data['dropoffText']?.toString() ?? '';
  final String fare = message.data['fare']?.toString() ?? '';

  final callKitParams = CallKitParams(
    id: callUuid,
    nameCaller: fare.isNotEmpty ? 'New Ride ($fare)' : 'New Ride Request',
    appName: 'Flising Driver',
    avatar: message.data['passengerPhoto']?.toString() ?? '',
    handle: dropoff.isNotEmpty ? '$pickup ➔ $dropoff' : pickup,
    type: 0,
    duration: 30000,
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: 'Missed ride request',
    ),
    extra: message.data,
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#1C1C1E',
      actionColor: '#E9692C',
      textColor: '#FFFFFF',
      incomingCallNotificationChannelName: 'Incoming Ride Requests',
      isShowCallID: true,
      isShowFullLockedScreen: true,
    ),
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
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        "rationaleMessagePermission": "Notification permission is required to show incoming ride requests.",
        "postNotificationMessageRequired": "Please allow notifications in settings to receive ride requests."
      });
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}

    await saveToken();
    _fcm.onTokenRefresh.listen((_) => saveToken());
    FirebaseMessaging.onMessage.listen((message) async {
      if (message.data['type'] == 'RIDE_CANCELLED') {
        await FlutterCallkitIncoming.endAllCalls();
      }
    });
  }

  static Future<void> saveToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await _fcm.getToken();
    if (token == null) return;
    await FirebaseDatabase.instanceFor(
            app: Firebase.app(),
            databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app')
        .ref('drivers/${user.uid}/fcmToken')
        .set(token);
  }
}
