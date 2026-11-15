import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter/material.dart';
import 'driver_chat_screen.dart';
import 'driver_call_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';

import 'live_map.dart';
import 'driver_profile.dart';
import 'earnings_tracker.dart';

class DriverMainScreen extends StatefulWidget {
  const DriverMainScreen({super.key});

  @override
  State<DriverMainScreen> createState() => _DriverMainScreenState();
}

class _DriverMainScreenState extends State<DriverMainScreen> {
  int selectedView = 1;
  bool _isOnline = false;
  bool _isToggleLoading = false;
  bool _isVerified = false;

  StreamSubscription<DatabaseEvent>? _rideSubscription;
  StreamSubscription<DatabaseEvent>? _incomingCallListener;
  bool _callScreenOpen = false;
  bool _isDelivery = false;
  bool _recipientPays = false;
  String _recipientName = '';
  String _recipientPhone = '';
  String _parcelNote = '';
  String _deliveryPin = '';
  StreamSubscription<DatabaseEvent>? _activeRideListener;
  bool _isRidePopupShowing = false;

  String? _activeRideId;
  String _activeRideStatus = 'IDLE';
  String _passengerPickup = "";
  String _passengerDropoff = "";

  // Passenger info for call/chat
  String? _passengerName;
  String? _passengerPhoto;

  Timer? _movementTimer;
  double _currentLat = -2.6741;
  double _currentLng = 141.3028;

  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);
  final Color onlineGreen = const Color(0xFF4CAF50);
  final Color offlineRed = const Color(0xFFD32F2F);

  @override
  void initState() {
    super.initState();
    _restoreActiveRide();
    _saveFcmToken();
    _listenForRideRequests();
    _loadVerificationStatus();
  }

  @override
  Future<void> _loadDelivery(String rideId) async {
    final snap = await FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref('rides/$rideId').get();
    if (!mounted || snap.value == null) return;
    final d = snap.value as Map<dynamic, dynamic>;
    setState(() {
      _isDelivery = d['type'] == 'delivery';
      _recipientPays = d['payer'] == 'recipient';
      _recipientName = (d['recipientName'] ?? '').toString();
      _recipientPhone = (d['recipientPhone'] ?? '').toString();
      _parcelNote = (d['parcelNote'] ?? '').toString();
      _deliveryPin = (d['deliveryPin'] ?? '').toString();
    });
  }

  Future<void> _callRecipient() async {
    if (_recipientPhone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: _recipientPhone),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _restoreActiveRide() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app').ref('rides').orderByChild('assignedDriverId').equalTo(uid).limitToLast(10).get();
    if (!mounted || snap.value == null) return;
    final rides = snap.value as Map<dynamic, dynamic>;
    String? bestId;
    Map? best;
    int bestTs = -1;
    for (final entry in rides.entries) {
      final r = entry.value;
      if (r is! Map) continue;
      if (r['status'] != 'ACCEPTED' && r['status'] != 'IN_PROGRESS') continue;
      final ts = r['timestamp'] is num ? (r['timestamp'] as num).toInt() : 0;
      if (ts > bestTs) { bestTs = ts; bestId = entry.key.toString(); best = r; }
    }
    for (final entry in rides.entries) {
      final r = entry.value;
      if (r is! Map) continue;
      if (r['status'] != 'ACCEPTED' && r['status'] != 'IN_PROGRESS') continue;
      final String id = entry.key.toString();
      if (id != bestId) {
        FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app').ref('rides/$id').update({'status': 'CANCELLED_SYSTEM_CLEANUP'});
      }
    }

    if (bestId == null || best == null) return;
    final String id = bestId!;
    final Map r = best!;
    setState(() {
      _activeRideId = id;
      _activeRideStatus = r['status'].toString();
      _passengerPickup = (r['pickupText'] ?? '').toString();
      _passengerDropoff = (r['dropoffText'] ?? '').toString();
      _passengerName = r['passengerName']?.toString();
      _passengerPhoto = r['passengerPhoto']?.toString();
    });
    _watchIncomingCall(id);
    _loadDelivery(id);
    _listenForCancellations(id);
  }

  Future<void> _finishWithoutPin() async {
    if (_activeRideId != null) {
      await FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app').ref('rides/$_activeRideId').update({'pinBypassed': true});
    }
    _updateMeter('COMPLETED');
  }

  void _askDeliveryPin() {
    final ctrl = TextEditingController();
    String? err;
    int tries = 0;
    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (sCtx, setD) => AlertDialog(
          backgroundColor: darkSurface,
          title: const Text('Delivery PIN', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
            decoration: InputDecoration(
              hintText: 'Ask the recipient',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 0),
              errorText: err,
            ),
          ),
          actions: [
            if (tries >= 3)
              TextButton(
                onPressed: () { Navigator.pop(dCtx); _finishWithoutPin(); },
                child: const Text('FINISH WITHOUT PIN', style: TextStyle(color: Colors.redAccent)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                if (_deliveryPin.isEmpty || ctrl.text.trim() == _deliveryPin) {
                  Navigator.pop(dCtx);
                  _updateMeter('COMPLETED');
                } else {
                  setD(() { tries++; err = tries >= 3 ? 'Still wrong. Call the sender for the PIN' : 'Wrong PIN, check with the recipient'; });
                }
              },
              child: const Text('CONFIRM'),
            ),
          ],
        ),
      ),
    );
  }

  void _watchIncomingCall(String rideId) {
    _incomingCallListener?.cancel();
    _callkitEventSub?.cancel();
    _incomingCallListener = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref('rides/$rideId/call').onValue.listen((event) {
      if (!event.snapshot.exists || !mounted || _callScreenOpen) return;
      final data = event.snapshot.value as Map<dynamic, dynamic>;
      if (_activeRideStatus == 'IN_PROGRESS' || data['status'] != 'CALLING') return;
      if (data['callerType'] != 'passenger') return;
      _callScreenOpen = true;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => DriverCallScreen(
          rideId: rideId,
          isIncoming: true,
          otherPersonName: _passengerName ?? 'Passenger',
          otherPersonPhoto: _passengerPhoto,
        ),
      )).then((_) => _callScreenOpen = false);
    });
  }

  void _stopWatchingIncomingCall() {
    _incomingCallListener?.cancel();
    _incomingCallListener = null;
  }

  void dispose() {
    _incomingCallListener?.cancel();
    _rideSubscription?.cancel();
    _activeRideListener?.cancel();
    _movementTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveFcmToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
      ).ref('drivers/${user.uid}/fcmToken').set(token);
    }
  }

  StreamSubscription? _callkitEventSub;

  void _setupCallkitListener() {
    _callkitEventSub?.cancel();
    _callkitEventSub = FlutterCallkitIncoming.onEvent.listen((dynamic event) async {
      if (event == null) return;
      final eventStr = event.toString();

      if (eventStr.contains('Accept') || eventStr.contains('ACCEPT')) {
        try { await FlutterCallkitIncoming.endAllCalls(); } catch (_) {}
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _checkPendingRidesNow();
        });
      } else if (eventStr.contains('Decline') || eventStr.contains('DECLINE')) {
        try { await FlutterCallkitIncoming.endAllCalls(); } catch (_) {}
        await _declinePendingRidesFromCallkit();
      }
    });
  }

  Future<void> _declinePendingRidesFromCallkit() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final dbRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
      ).ref();
      final snap = await dbRef.child('rides').orderByChild('assignedDriverId').equalTo(currentUser.uid).get();
      if (!snap.exists || snap.value == null) return;
      final rides = snap.value as Map<dynamic, dynamic>;
      for (final entry in rides.entries) {
        final rideId = entry.key.toString();
        final rideData = entry.value;
        if (rideData is Map && rideData['status'] == 'PENDING') {
          _handledRideIds.add(rideId);
          await dbRef.child('drivers/${currentUser.uid}/currentRideId').remove();
          await dbRef.child('rides/$rideId').update({'status': 'IGNORED'});
        }
      }
    } catch (_) {}
  }

  Future<void> _checkPendingRidesNow() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || !mounted) return;
    try {
      final snap = await FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
      ).ref('rides').orderByChild('assignedDriverId').equalTo(currentUser.uid).get();

      if (!mounted || !snap.exists || snap.value == null) return;
      final rides = snap.value as Map<dynamic, dynamic>;
      rides.forEach((rideId, rideData) {
        if (rideData is Map &&
            rideData['status'] == 'PENDING' &&
            !_handledRideIds.contains(rideId) &&
            !_isRidePopupShowing &&
            _activeRideStatus == 'IDLE') {
          _showRideRequestPopup(rideId.toString(), rideData);
        }
      });
    } catch (_) {}
  }

  void _loadVerificationStatus() {
    _setupCallkitListener();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    );
    db.ref('drivers/${user.uid}/profile/isVerified').onValue.listen((event) {
      if (mounted) {
        setState(() => _isVerified = (event.snapshot.value as bool?) ?? false);
      }
    });
    db.ref('drivers/${user.uid}/isOnline').onValue.listen((event) {
      if (mounted && event.snapshot.exists) {
        final onlineVal = (event.snapshot.value as bool?) ?? false;
        setState(() => _isOnline = onlineVal);
        if (onlineVal) {
          _checkPendingRidesNow();
        }
      }
    });
  }

  void _listenForRideRequests() {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    DatabaseReference ridesRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref().child('rides');

    _rideSubscription = ridesRef
        .orderByChild('assignedDriverId')
        .equalTo(currentUser.uid)
        .onValue
        .listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists && event.snapshot.value != null) {
        Map<dynamic, dynamic> rides =
            event.snapshot.value as Map<dynamic, dynamic>;
        rides.forEach((rideId, rideData) {
          if (rideData is Map &&
              rideData['status'] == 'PENDING' &&
              !_handledRideIds.contains(rideId) &&
              !_isRidePopupShowing &&
              _activeRideStatus == 'IDLE') {
            final ts = rideData['timestamp'];
            if (ts is num) {
              final ageSec = ((DateTime.now().millisecondsSinceEpoch - ts.toInt()) / 1000).round();
              if (ageSec > 35) {
                _handledRideIds.add(rideId.toString());
                return;
              }
            }
            _showRideRequestPopup(rideId.toString(), rideData);
          }
        });
      }
    });
  }

  final Set<String> _handledRideIds = {};

  void _showRideRequestPopup(String rideId, dynamic rideData) {
    _handledRideIds.add(rideId);
    _isRidePopupShowing = true;
    int timeLeft = 30;
    if (rideData is Map && rideData['timestamp'] is num) {
      final elapsed = ((DateTime.now().millisecondsSinceEpoch - (rideData['timestamp'] as num).toInt()) / 1000).round();
      timeLeft = (30 - elapsed).clamp(5, 30);
    }
    Timer? countdownTimer;
    StreamSubscription<DatabaseEvent>? cancelSub;
    BuildContext? activeDialogCtx;

    // Dismiss any CallKit screen now that the in-app popup is visible
    try { FlutterCallkitIncoming.endAllCalls(); } catch (_) {}

    String pickup = (rideData['type'] == 'delivery' ? '📦 DELIVERY • ' : '') + (rideData['pickupText'] ?? 'Unknown Pickup');
    String dropoff = rideData['dropoffText'] ?? 'Unknown Dropoff';
    String fare = rideData['fare'] ?? 'K 0.00';
    if (rideData['payer'] == 'recipient') fare = '$fare • recipient pays';

    cancelSub = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref('rides/$rideId/status').onValue.listen((event) {
      final st = event.snapshot.value?.toString() ?? '';
      if (st.isEmpty || st.startsWith('CANCELLED') || st == 'IGNORED' || st == 'TIMEOUT' || st == 'EXPIRED') {
        countdownTimer?.cancel();
        cancelSub?.cancel();
        try { FlutterCallkitIncoming.endAllCalls(); } catch (_) {}
        if (activeDialogCtx != null && mounted) {
          Navigator.of(activeDialogCtx!).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ride request was cancelled by passenger.'), backgroundColor: Colors.orange),
          );
        }
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        activeDialogCtx = dialogContext;
        return StatefulBuilder(builder: (context, setStateDialog) {
          countdownTimer ??=
              Timer.periodic(const Duration(seconds: 1), (timer) {
            if (timeLeft > 0) {
              setStateDialog(() => timeLeft--);
            } else {
              timer.cancel();
              _handleRideAction(
                  rideId, 'IGNORED', dialogContext, pickup, dropoff);
            }
          });

          return AlertDialog(
            backgroundColor: darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: flisingOrange, width: 2),
            ),
            title: Text('NEW RIDE REQUEST',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: flisingOrange,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '00:${timeLeft.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color:
                          timeLeft <= 10 ? offlineRed : Colors.white,
                      fontSize: 45,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2),
                ),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.my_location,
                            color: Colors.blueAccent, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(pickup,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14)))
                      ]),
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child:
                              Divider(color: Colors.white24, height: 1)),
                      Row(children: [
                        Icon(Icons.location_on,
                            color: flisingOrange, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(dropoff,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14)))
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Est. Fare: $fare',
                    style: TextStyle(
                        color: onlineGreen,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              OutlinedButton(
                onPressed: () {
                  countdownTimer?.cancel();
                  _handleRideAction(
                      rideId, 'IGNORED', dialogContext, pickup, dropoff);
                },
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: offlineRed),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: const Size(100, 45)),
                child: Text('IGNORE',
                    style: TextStyle(
                        color: offlineRed,
                        fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () {
                  countdownTimer?.cancel();
                  _handleRideAction(
                      rideId, 'ACCEPTED', dialogContext, pickup, dropoff);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: flisingOrange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: const Size(100, 45)),
                child: const Text('ACCEPT',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    ).then((_) {
      countdownTimer?.cancel();
      cancelSub?.cancel();
      _isRidePopupShowing = false;
    });
  }

  void _handleRideAction(
    String rideId,
    String action,
    BuildContext dialogContext,
    String pickup,
    String dropoff,
  ) async {
    try { FlutterCallkitIncoming.endAllCalls(); } catch (_) {}
    if (Navigator.canPop(dialogContext)) {
      Navigator.pop(dialogContext);
    }

    User? currentUser = FirebaseAuth.instance.currentUser;
    final dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    if (action == 'IGNORED') {
      await dbRef
          .child('drivers/${currentUser?.uid}/currentRideId')
          .remove();
      await dbRef.child('rides/$rideId').update({'status': 'IGNORED'});
    } else if (action == 'ACCEPTED') {
      final preSnap = await dbRef.child('rides/$rideId').get();
      if (!preSnap.exists || preSnap.value is! Map) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ride request expired or was removed.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }
      final preMap = preSnap.value as Map;
      final liveStatus = (preMap['status'] ?? '').toString();
      if (liveStatus != 'PENDING') {
        await dbRef.child('drivers/${currentUser?.uid}/currentRideId').remove();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ride is no longer available ($liveStatus).'), backgroundColor: Colors.orange),
          );
        }
        return;
      }
      String drvName = currentUser?.displayName ?? 'Flising Driver';
      String? drvPhoto;
      String? drvCarModel;
      String? drvPlate;
      try {
        final pSnap = await dbRef.child('drivers/${currentUser?.uid}/profile').get();
        if (pSnap.exists && pSnap.value is Map) {
          final pMap = pSnap.value as Map;
          if (pMap['fullName'] != null && pMap['fullName'].toString().trim().isNotEmpty) {
            drvName = pMap['fullName'].toString().trim();
          }
          drvPhoto = pMap['profileImageUrl']?.toString();
          drvCarModel = pMap['carModel']?.toString();
          drvPlate = pMap['plateNumber']?.toString();
        }
      } catch (_) {}
      final drvFirst = drvName.split(' ').first;
      await dbRef.child('rides/$rideId').update({
        'status': 'ACCEPTED',
        'driverName': drvName,
        'driverFirstName': drvFirst,
        'if_photo': drvPhoto,
        if (drvPhoto != null) 'driverPhoto': drvPhoto,
        if (drvCarModel != null) 'carModel': drvCarModel,
        if (drvPlate != null) 'plateNumber': drvPlate,
      });

      // Try to fetch passenger display info
      String? passengerName;
      String? passengerPhoto;
      try {
        final rideSnap = await dbRef.child('rides/$rideId').get();
        if (rideSnap.value != null) {
          final rideMap = rideSnap.value as Map<dynamic, dynamic>;
          passengerName = rideMap['passengerName'];
          passengerPhoto = rideMap['passengerPhoto'];
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _activeRideId = rideId; _watchIncomingCall(rideId); _loadDelivery(rideId);
        _activeRideStatus = 'ACCEPTED';
        _passengerPickup = pickup;
        _passengerDropoff = dropoff;
        _passengerName = passengerName;
        _passengerPhoto = passengerPhoto;
      });
      _listenForCancellations(rideId);
    }
  }

  Future<void> _navigateToPickup(String rideId) async {
    final snap = await FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref('rides/$rideId').get();
    if (snap.value == null) return;
    final data = snap.value as Map<dynamic, dynamic>;
    final lat = data['pickupLat'];
    final lng = data['pickupLng'];
    if (lat == null || lng == null) return;
    final url = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      final fallback = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _navigateToDropoff(String rideId) async {
    final snap = await FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref('rides/$rideId').get();
    if (snap.value == null) return;
    final data = snap.value as Map<dynamic, dynamic>;
    final lat = data['dropoffLat'];
    final lng = data['dropoffLng'];
    if (lat == null || lng == null) return;
    final url = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      final fallback = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  void _listenForCancellations(String rideId) {
    _activeRideListener?.cancel();
    _activeRideListener = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref().child('rides/$rideId').onValue.listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists || event.snapshot.value == null) {
        setState(() {
          _activeRideId = null; _stopWatchingIncomingCall(); _isDelivery = false;
          _activeRideStatus = 'IDLE';
          _passengerName = null;
          _passengerPhoto = null;
        });
        _activeRideListener?.cancel();
        return;
      }
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final st = (data['status'] ?? '').toString();
        if (st.startsWith('CANCELLED') || st == 'TIMEOUT' || st == 'EXPIRED' || st == 'IGNORED') {
          setState(() {
            _activeRideId = null; _stopWatchingIncomingCall(); _isDelivery = false;
            _activeRideStatus = 'IDLE';
            _passengerName = null;
            _passengerPhoto = null;
          });
          _activeRideListener?.cancel();

          User? currentUser = FirebaseAuth.instance.currentUser;
          FirebaseDatabase.instanceFor(
            app: Firebase.app(),
            databaseURL:
                'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
          ).ref().child('drivers/${currentUser?.uid}/currentRideId').remove();

          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: darkSurface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: offlineRed, width: 2)),
              title: Text("RIDE CANCELLED",
                  style: TextStyle(
                      color: offlineRed,
                      fontWeight: FontWeight.bold)),
              content: const Text(
                  "The passenger has cancelled the ride request.",
                  style: TextStyle(color: Colors.white70)),
              actions: [
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: offlineRed),
                    child: const Text("OK",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)))
              ],
            ),
          );
        }
      }
    });
  }

  void _updateMeter(String newStatus) async {
    if (_activeRideId == null) return;
    User? currentUser = FirebaseAuth.instance.currentUser;
    final dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    await dbRef.child('rides/$_activeRideId').update({'status': newStatus});

    if (newStatus == 'COMPLETED') {
      await dbRef
          .child('drivers/${currentUser?.uid}/currentRideId')
          .remove();
    }

    if (!mounted) return;
    setState(() {
      if (newStatus == 'COMPLETED') {
        _activeRideId = null; _stopWatchingIncomingCall(); _isDelivery = false;
        _activeRideStatus = 'IDLE';
        _passengerName = null;
        _passengerPhoto = null;
        _activeRideListener?.cancel();
      } else {
        _activeRideStatus = newStatus;
        if (newStatus == 'IN_PROGRESS') _stopWatchingIncomingCall();
      }
    });
  }


  void _showRateCardDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: flisingOrange, width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: flisingOrange),
            const SizedBox(width: 10),
            const Text(
              'OFFICIAL RATE CARD',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rateRow(Icons.directions_car, 'Car Ride', 'K 6.70 / km', 'Standard passenger trip'),
            const SizedBox(height: 10),
            _rateRow(Icons.two_wheeler, 'Motorcycle', 'K 5.50 / km', 'Fast solo rider trip'),
            const SizedBox(height: 10),
            _rateRow(Icons.inventory_2, 'Parcel Delivery', 'K 5.00 / km', 'Send packages & goods'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Fares are calculated by exact OSRM road driving distance.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('• All totals are rounded to the nearest 10 toea (K 0.10).', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('• Platform Service Fee (Flising Share): 10% per completed trip.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: flisingOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('CLOSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rateRow(IconData icon, String title, String rate, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: flisingOrange, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          Text(rate, style: TextStyle(color: onlineGreen, fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  void _showManualRideDialog() {
    if (!_isVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete verification first to start a ride.'), backgroundColor: Colors.red),
      );
      return;
    }

    final List> presets = [
      {'name': 'Vanimo Main Market', 'lat': -2.6775, 'lng': 141.3018},
      {'name': 'BSP Bank Vanimo', 'lat': -2.6738, 'lng': 141.3029},
      {'name': 'Vanimo Airport', 'lat': -2.6917, 'lng': 141.3022},
      {'name': 'Vanimo General Hospital', 'lat': -2.6719, 'lng': 141.3061},
      {'name': 'Dalai / Wesan', 'lat': -2.6852, 'lng': 141.2965},
      {'name': 'Greenhills', 'lat': -2.6995, 'lng': 141.2980},
      {'name': 'Lido Village', 'lat': -2.6625, 'lng': 141.2810},
      {'name': 'Wutung Border Post', 'lat': -2.6033, 'lng': 141.0019},
    ];

    final passengerCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    String vehicleType = 'Car';
    Map<String, dynamic> selectedDest = presets[0];
    double? roadKm;
    String fareText = 'Calculating...';
    bool isCalc = false;
    bool isStarting = false;

    Future<void> calcFare(StateSetter setD) async {
      setD(() { isCalc = true; fareText = 'Calculating...'; });
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        _currentLat = pos.latitude;
        _currentLng = pos.longitude;
      } catch (_) {}

      final oLat = _currentLat == 0.0 ? -2.6741 : _currentLat;
      final oLng = _currentLng == 0.0 ? 141.3028 : _currentLng;
      final dLat = (selectedDest['lat'] as num).toDouble();
      final dLng = (selectedDest['lng'] as num).toDouble();

      double km = 1.5;
      try {
        final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/$oLng,$oLat;$dLng,$dLat?overview=false',
        );
        final resp = await http.get(url);
        final data = json.decode(resp.body);
        if (data['code'] == 'Ok' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final meters = (data['routes'][0]['distance'] as num).toDouble();
          km = meters / 1000.0;
        }
      } catch (_) {}

      if (km < 0.5) km = 0.5;
      final rate = vehicleType == 'Car' ? 6.70 : 5.50;
      final raw = km * rate;
      final rounded = (raw * 10).round() / 10.0;
      roadKm = km;
      setD(() {
        isCalc = false;
        fareText = 'K ${rounded.toStringAsFixed(2)}';
      });
    }

    showDialog(
      context: context,
      builder: (ctx) {
        bool initCalled = false;
        return StatefulBuilder(
          builder: (sCtx, setD) {
            if (!initCalled) {
              initCalled = true;
              Future.microtask(() => calcFare(setD));
            }
            return AlertDialog(
              backgroundColor: darkSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: flisingOrange, width: 1.5),
              ),
              title: Row(
                children: [
                  Icon(Icons.hail, color: flisingOrange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'STREET HAIL (MANUAL RIDE)',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Car (K6.70/km)'),
                            selected: vehicleType == 'Car',
                            selectedColor: flisingOrange,
                            backgroundColor: Colors.black,
                            labelStyle: TextStyle(color: vehicleType == 'Car' ? Colors.white : Colors.white70, fontSize: 12),
                            onSelected: (_) {
                              vehicleType = 'Car';
                              calcFare(setD);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Bike (K5.50/km)'),
                            selected: vehicleType == 'Motorcycle',
                            selectedColor: flisingOrange,
                            backgroundColor: Colors.black,
                            labelStyle: TextStyle(color: vehicleType == 'Motorcycle' ? Colors.white : Colors.white70, fontSize: 12),
                            onSelected: (_) {
                              vehicleType = 'Motorcycle';
                              calcFare(setD);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Select Dropoff Destination:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedDest['name'] as String,
                          dropdownColor: darkSurface,
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          items: presets.map((p) {
                            return DropdownMenuItem<String>(
                              value: p['name'] as String,
                              child: Text(p['name'] as String),
                            );
                          }).toList(),
                          onChanged: (val) {
                            final match = presets.firstWhere((e) => e['name'] == val, orElse: () => presets[0]);
                            selectedDest = match;
                            calcFare(setD);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Or search place in Vanimo...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                              filled: true,
                              fillColor: Colors.black,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: flisingOrange),
                          icon: const Icon(Icons.search, color: Colors.white, size: 20),
                          onPressed: () async {
                            final q = searchCtrl.text.trim();
                            if (q.isEmpty) return;
                            setD(() => isCalc = true);
                            try {
                              final u = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent("$q, Vanimo, Papua New Guinea")}&format=json&limit=1');
                              final r = await http.get(u, headers: {'User-Agent': 'FlisingDriverApp/2.3'});
                              final list = json.decode(r.body) as List;
                              if (list.isNotEmpty) {
                                final item = list[0];
                                final custom = {
                                  'name': q,
                                  'lat': double.parse(item['lat'].toString()),
                                  'lng': double.parse(item['lon'].toString()),
                                };
                                presets.insert(0, custom);
                                selectedDest = custom;
                                await calcFare(setD);
                              } else {
                                setD(() => isCalc = false);
                              }
                            } catch (_) {
                              setD(() => isCalc = false);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passengerCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Passenger Name or Phone (Optional)',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.person_outline, color: Colors.white54, size: 18),
                        filled: true,
                        fillColor: Colors.black,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: flisingOrange.withOpacity(0.5)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            roadKm != null ? 'Road Distance: ${roadKm!.toStringAsFixed(1)} km' : 'Calculating road distance...',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isCalc ? 'Calculating...' : fareText,
                            style: TextStyle(color: onlineGreen, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: isCalc || isStarting
                      ? null
                      : () async {
                          setD(() => isStarting = true);
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) return;
                          final db = FirebaseDatabase.instanceFor(
                            app: Firebase.app(),
                            databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
                          ).ref();
                          final newRef = db.child('rides').push();
                          final rideId = newRef.key!;
                          final pName = passengerCtrl.text.trim().isEmpty
                              ? 'Street-Hail Passenger'
                              : passengerCtrl.text.trim();
                          final oLat = _currentLat == 0.0 ? -2.6741 : _currentLat;
                          final oLng = _currentLng == 0.0 ? 141.3028 : _currentLng;
                          final dLat = (selectedDest['lat'] as num).toDouble();
                          final dLng = (selectedDest['lng'] as num).toDouble();
                          final dName = selectedDest['name'].toString();

                          await newRef.set({
                            'passengerId': 'street_hail',
                            'passengerName': pName,
                            'assignedDriverId': user.uid,
                            'driverName': user.displayName ?? 'Flising Driver',
                            'pickupText': 'Street Hail (Current GPS)',
                            'dropoffText': dName,
                            'pickupLat': oLat,
                            'pickupLng': oLng,
                            'dropoffLat': dLat,
                            'dropoffLng': dLng,
                            'fare': fareText,
                            'vehicleType': vehicleType,
                            'paymentMethod': 'CASH',
                            'type': 'street_hail',
                            'status': 'IN_PROGRESS',
                            'timestamp': ServerValue.timestamp,
                          });

                          await db.child('drivers/${user.uid}/currentRideId').set(rideId);

                          if (!mounted) return;
                          Navigator.pop(ctx);
                          setState(() {
                            selectedView = 1;
                            _activeRideId = rideId;
                            _activeRideStatus = 'IN_PROGRESS';
                            _passengerName = pName;
                            _passengerPhoto = null;
                            _passengerPickup = 'Street Hail (Current GPS)';
                            _passengerDropoff = dName;
                            _isDelivery = false;
                          });
                          _listenForCancellations(rideId);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: flisingOrange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('START STREET RIDE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleStatus() async {
    setState(() => _isToggleLoading = true);
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      bool newStatus = !_isOnline;
      Map<String, dynamic> updatePayload = {
        'isOnline': newStatus,
        'lastUpdated': ServerValue.timestamp,
      };

      if (newStatus == true) {
        try {
          final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high));
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
        } catch (_) {}
        updatePayload['latitude'] = _currentLat;
        updatePayload['longitude'] = _currentLng;
      } else {
        updatePayload['latitude'] = null;
        updatePayload['longitude'] = null;
        updatePayload['currentRideId'] = null;
      }

      await FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
      ).ref().child('drivers/${currentUser.uid}').update(updatePayload);

      if (!mounted) return;
      setState(() {
        _isOnline = newStatus;
        _isToggleLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isToggleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          IndexedStack(
            index: selectedView,
            children: const [
              EarningsTracker(),
              LiveMap(),
              DriverProfile(),
            ],
          ),

          if (_activeRideStatus == 'IDLE')
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: ElevatedButton(
                        onPressed: _isToggleLoading || !_isVerified
                            ? null
                            : _toggleStatus,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isOnline ? onlineGreen : offlineRed,
                          disabledBackgroundColor: _isOnline
                              ? onlineGreen.withOpacity(0.6)
                              : offlineRed.withOpacity(0.6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                          elevation: 8,
                          shadowColor: Colors.black.withOpacity(0.5),
                        ),
                        child: _isToggleLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 3))
                            : Text(
                                _isOnline ? 'ONLINE' : 'OFFLINE',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.5),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _showRateCardDialog,
                          icon: Icon(Icons.receipt_long, color: flisingOrange, size: 16),
                          label: const Text('Rate Card', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: darkSurface,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: flisingOrange.withOpacity(0.6)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: _showManualRideDialog,
                          icon: Icon(Icons.hail, color: onlineGreen, size: 16),
                          label: const Text('Street Hail', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: darkSurface,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: onlineGreen.withOpacity(0.6)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!_isVerified)
                      Container(
                        width: double.infinity,
                        color: const Color(0xFFB71C1C),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: const Text(
                          'Please go to the "Verification Portal" on your profile and complete verification in order to go online and accept rides.',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          if (_activeRideStatus != 'IDLE')
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: darkSurface,
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: flisingOrange, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: flisingOrange.withOpacity(0.15),
                        blurRadius: 20,
                        spreadRadius: 2)
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor:
                              flisingOrange.withOpacity(0.2),
                          backgroundImage: _passengerPhoto != null
                              ? NetworkImage(_passengerPhoto!)
                              : null,
                          child: _passengerPhoto == null
                              ? Icon(Icons.person,
                                  color: flisingOrange, size: 30)
                              : null,
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Text("Passenger",
                                  style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12)),
                              Text(
                                _passengerName ?? "Flising User",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (_activeRideStatus == 'ACCEPTED') ...[
                          GestureDetector(
                            onTap: () {
                              if (_activeRideId == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DriverChatScreen(
                                    rideId: _activeRideId!,
                                    otherPersonName: _passengerName ?? 'Passenger',
                                    otherPersonPhoto: _passengerPhoto,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                              child: const Icon(Icons.chat, color: Colors.white, size: 20),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (_activeRideId == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DriverCallScreen(
                                    rideId: _activeRideId!,
                                    otherPersonName: _passengerName ?? 'Passenger',
                                    otherPersonPhoto: _passengerPhoto,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: onlineGreen.withOpacity(0.2), shape: BoxShape.circle),
                              child: Icon(Icons.phone, color: onlineGreen, size: 22),
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline, color: Colors.white54, size: 14),
                                SizedBox(width: 4),
                                Text("Calls locked on trip", style: TextStyle(color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Row(children: [
                            const Icon(Icons.my_location,
                                color: Colors.blueAccent, size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(_passengerPickup,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13)))
                          ]),
                          const Padding(
                              padding:
                                  EdgeInsets.symmetric(vertical: 6),
                              child: Divider(
                                  color: Colors.white24, height: 1)),
                          Row(children: [
                            Icon(Icons.location_on,
                                color: flisingOrange, size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(_passengerDropoff,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13)))
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_isDelivery)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: flisingOrange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: flisingOrange.withOpacity(0.5)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.inventory_2, color: Colors.white70),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Deliver to $_recipientName',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                if (_parcelNote.isNotEmpty)
                                  Text(_parcelNote,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                Text(_recipientPays ? 'Collect fare from RECIPIENT' : 'Collect fare from SENDER',
                                    style: TextStyle(color: flisingOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _callRecipient,
                            icon: const Icon(Icons.phone, color: Colors.greenAccent),
                          ),
                        ]),
                      ),
                    if (_activeRideStatus == 'ACCEPTED')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _navigateToPickup(_activeRideId!),
                            icon: const Icon(Icons.navigation, color: Colors.blueAccent),
                            label: const Text('NAVIGATE TO PICKUP',
                                style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.blueAccent),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_activeRideStatus == 'ACCEPTED') {
                            _updateMeter('IN_PROGRESS');
                            _navigateToDropoff(_activeRideId!);
                          } else if (_activeRideStatus ==
                              'IN_PROGRESS') {
                            if (_isDelivery) { _askDeliveryPin(); } else { _updateMeter('COMPLETED'); }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _activeRideStatus == 'ACCEPTED'
                                  ? flisingOrange
                                  : onlineGreen,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text(
                          _activeRideStatus == 'ACCEPTED'
                              ? (_isDelivery ? 'PARCEL PICKED UP' : 'PICKUP PASSENGER')
                              : (_isDelivery ? 'ENTER DELIVERY PIN' : 'END RIDE & COLLECT FARE'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 1.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _activeRideStatus == 'IDLE'
          ? Container(
              decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(
                          color: Colors.white10, width: 1))),
              child: BottomNavigationBar(
                backgroundColor: Colors.black,
                selectedItemColor: flisingOrange,
                unselectedItemColor: Colors.white54,
                currentIndex: selectedView,
                onTap: (index) =>
                    setState(() => selectedView = index),
                type: BottomNavigationBarType.fixed,
                items: const [
                  BottomNavigationBarItem(
                      icon: Icon(
                          Icons.account_balance_wallet_outlined),
                      activeIcon:
                          Icon(Icons.account_balance_wallet),
                      label: 'Earnings'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.map_outlined),
                      activeIcon: Icon(Icons.map),
                      label: 'Live Map'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline),
                      activeIcon: Icon(Icons.person),
                      label: 'Profile'),
                ],
              ),
            )
          : null,
    );
  }
}
