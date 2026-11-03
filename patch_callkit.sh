#!/bin/bash
FILE="$HOME/flising-driver-app/lib/notification_service.dart"

# 1. Add CallKit imports to the top of the file
sed -i '1i import "package:flutter_callkit_incoming/entities/entities.dart";\nimport "package:flutter_callkit_incoming/flutter_callkit_incoming.dart";' "$FILE"

# 2. Replace the background handler with the CallKit trigger
sed -i '/Future<void> firebaseMessagingBackgroundHandler/,/}/c \
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {\
  print('\''Background message: ${message.notification?.title}'\'');\
  final callKitParams = CallKitParams(\
    id: message.data['\''rideId'\''] ?? DateTime.now().millisecondsSinceEpoch.toString(),\
    nameCaller: '\''New Ride Request'\'',\
    appName: '\''Flising Driver'\'',\
    avatar: message.data['\''passengerPhoto'\''] ?? '\'''\'',\
    handle: message.data['\''pickupText'\''] ?? (message.notification?.body ?? '\''Open app to accept'\''),\
    type: 0,\
    duration: 30000,\
    textAccept: '\''OPEN APP'\'',\
    textDecline: '\''DISMISS'\'',\
    missedCallNotification: const NotificationParams(\
      showNotification: true,\
      isShowCallback: false,\
      subtitle: '\''Missed ride request'\'',\
    ),\
    extra: message.data,\
  );\
  await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);\
}' "$FILE"

echo "CallKit patch applied successfully."
