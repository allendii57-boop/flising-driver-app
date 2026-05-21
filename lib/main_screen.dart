import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

// Your exact file names!
import 'live_map.dart';
import 'driver_profile.dart';
import 'earnings_tracker.dart';

class DriverMainScreen extends StatefulWidget {
  const DriverMainScreen({super.key});

  @override
  State<DriverMainScreen> createState() => _DriverMainScreenState();
}

class _DriverMainScreenState extends State<DriverMainScreen> {
  // Navigation & Status State
  int selectedView = 1; // Default to Live Map (index 1)
  bool _isOnline = false;
  bool _isToggleLoading = false;

  // Firebase Radar & Ride State
  StreamSubscription<DatabaseEvent>? _rideSubscription;
  StreamSubscription<DatabaseEvent>? _activeRideListener;
  bool _isRidePopupShowing = false;
  
  String? _activeRideId;
  String _activeRideStatus = 'IDLE';
  String _passengerPickup = "";
  String _passengerDropoff = "";

  // Ghost Driver State
  Timer? _movementTimer;
  double _currentLat = -2.6741; // Vanimo coords!
  double _currentLng = 141.3028;

  // Premium Theme Colors
  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);
  final Color onlineGreen = const Color(0xFF4CAF50);
  final Color offlineRed = const Color(0xFFD32F2F);

  @override
  void initState() {
    super.initState();
    _listenForRideRequests();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    _activeRideListener?.cancel();
    _movementTimer?.cancel();
    super.dispose();
  }

  // --- THE GHOST DRIVER ENGINE ---
  void _startGhostDriver() {
    _movementTimer?.cancel();
    _movementTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      _currentLat += 0.00015;
      _currentLng += 0.00015;

      DatabaseReference driverRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
      ).ref().child('drivers/${currentUser.uid}');

      await driverRef.update({'latitude': _currentLat, 'longitude': _currentLng});
    });
  }

  void _stopGhostDriver() {
    _movementTimer?.cancel();
  }

  // --- FIREBASE RADAR ---
  void _listenForRideRequests() {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    DatabaseReference ridesRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
    ).ref().child('rides');

    _rideSubscription = ridesRef.orderByChild('assignedDriverId').equalTo(currentUser.uid).onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists) {
        Map<dynamic, dynamic> rides = event.snapshot.value as Map<dynamic, dynamic>;
        rides.forEach((rideId, rideData) {
          if (rideData['status'] == 'PENDING' && !_isRidePopupShowing && _activeRideStatus == 'IDLE') {
            _showRideRequestPopup(rideId, rideData);
          }
        });
      }
    });
  }

  // --- PREMIUM RIDE REQUEST POPUP ---
  void _showRideRequestPopup(String rideId, dynamic rideData) {
    _isRidePopupShowing = true;
    int timeLeft = 30;
    Timer? countdownTimer;

    String pickup = rideData['pickupText'] ?? 'Unknown Pickup';
    String dropoff = rideData['dropoffText'] ?? 'Unknown Dropoff';
    String fare = rideData['fare'] ?? 'K 0.00';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (timeLeft > 0) {
                setStateDialog(() { timeLeft--; });
              } else {
                timer.cancel();
                _handleRideAction(rideId, 'IGNORED', dialogContext, pickup, dropoff);
              }
            });

            return AlertDialog(
              backgroundColor: darkSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: flisingOrange, width: 2),
              ),
              title: Text('NEW RIDE REQUEST', textAlign: TextAlign.center, style: TextStyle(color: flisingOrange, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('00:${timeLeft.toString().padLeft(2, '0')}', style: TextStyle(color: timeLeft <= 10 ? offlineRed : Colors.white, fontSize: 45, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 25),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [const Icon(Icons.my_location, color: Colors.blueAccent, size: 18), const SizedBox(width: 12), Expanded(child: Text(pickup, style: const TextStyle(color: Colors.white, fontSize: 14)))]),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.white24, height: 1)),
                        Row(children: [Icon(Icons.location_on, color: flisingOrange, size: 18), const SizedBox(width: 12), Expanded(child: Text(dropoff, style: const TextStyle(color: Colors.white, fontSize: 14)))]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Est. Fare: $fare', style:  TextStyle(color: onlineGreen, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              actionsAlignment: MainAxisAlignment.spaceEvenly,
              actions: [
                OutlinedButton(
                  onPressed: () {
                    countdownTimer?.cancel();
                    _handleRideAction(rideId, 'IGNORED', dialogContext, pickup, dropoff);
                  },
                  style: OutlinedButton.styleFrom(side: BorderSide(color: offlineRed), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), minimumSize: const Size(100, 45)),
                  child: Text('IGNORE', style: TextStyle(color: offlineRed, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: () {
                    countdownTimer?.cancel();
                    _handleRideAction(rideId, 'ACCEPTED', dialogContext, pickup, dropoff);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: flisingOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), minimumSize: const Size(100, 45)),
                  child: const Text('ACCEPT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    ).then((_) {
      countdownTimer?.cancel();
      _isRidePopupShowing = false;
    });
  }

  // --- ACTION HANDLER ---
  void _handleRideAction(String rideId, String action, BuildContext dialogContext, String pickup, String dropoff) async {
    Navigator.pop(dialogContext);
    
    DatabaseReference rideRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
    ).ref().child('rides/$rideId');

    await rideRef.update({'status': action});

    if (action == 'ACCEPTED') {
      if (!mounted) return;
      setState(() {
        _activeRideId = rideId;
        _activeRideStatus = 'ACCEPTED';
        _passengerPickup = pickup;
        _passengerDropoff = dropoff;
      });
      _startGhostDriver();
      _listenForCancellations(rideId); 
    }
  }

  // --- CANCELLATION RADAR ---
  void _listenForCancellations(String rideId) {
    _activeRideListener?.cancel();
    _activeRideListener = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
    ).ref().child('rides/$rideId').onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        if (data['status'] == 'CANCELLED_BY_PASSENGER') {
          setState(() {
            _activeRideId = null;
            _activeRideStatus = 'IDLE';
          });
          _stopGhostDriver();
          _activeRideListener?.cancel();

          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: darkSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: offlineRed, width: 2)),
              title: Text("RIDE CANCELLED", style: TextStyle(color: offlineRed, fontWeight: FontWeight.bold)),
              content: const Text("The passenger has cancelled the ride request.", style: TextStyle(color: Colors.white70)),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx), 
                  style: ElevatedButton.styleFrom(backgroundColor: offlineRed),
                  child: const Text("OK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                )
              ],
            )
          );
        }
      }
    });
  }

  void _updateMeter(String newStatus) async {
    if (_activeRideId == null) return;
    
    DatabaseReference rideRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
    ).ref().child('rides/$_activeRideId');

    await rideRef.update({'status': newStatus});

    if (!mounted) return;
    setState(() {
      if (newStatus == 'COMPLETED') {
        _activeRideId = null;
        _activeRideStatus = 'IDLE';
        _stopGhostDriver();
        _activeRideListener?.cancel();
      } else {
        _activeRideStatus = newStatus;
      }
    });
  }

  // --- ONLINE/OFFLINE TOGGLE ENGINE ---
  void _toggleStatus() async {
    setState(() { _isToggleLoading = true; });
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DatabaseReference driverRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
      ).ref().child('drivers/${currentUser.uid}');

      bool newStatus = !_isOnline;
      Map<String, dynamic> updatePayload = {
        'isOnline': newStatus,
        'lastUpdated': ServerValue.timestamp
      };

      if (newStatus == true) {
        updatePayload['latitude'] = _currentLat;
        updatePayload['longitude'] = _currentLng;
      } else {
        updatePayload['latitude'] = null;
        updatePayload['longitude'] = null;
      }

      await driverRef.update(updatePayload);
      if (!mounted) return;
      setState(() { 
        _isOnline = newStatus;
        _isToggleLoading = false; 
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _isToggleLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. The Base Layer: Map, Earnings, or Profile
          IndexedStack(
            index: selectedView,
            children: const [
              EarningsTracker(),
              LiveMap(),
              DriverProfile(),
            ],
          ),

          // 2. The Top Layer: Online/Offline Floating Toggle
          if (_activeRideStatus == 'IDLE')
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: ElevatedButton(
                    onPressed: _isToggleLoading ? null : _toggleStatus,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isOnline ? onlineGreen : offlineRed,
                      disabledBackgroundColor: _isOnline ? onlineGreen.withOpacity(0.6) : offlineRed.withOpacity(0.6),
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 8,
                      shadowColor: Colors.black.withOpacity(0.5),
                    ),
                    child: _isToggleLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : Text(
                            _isOnline ? 'ONLINE' : 'OFFLINE',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5),
                          ),
                  ),
                ),
              ),
            ),

          // 3. The Bottom Layer: Active Ride Passenger Panel
          if (_activeRideStatus != 'IDLE')
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: darkSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: flisingOrange, width: 1.5),
                  boxShadow: [BoxShadow(color: flisingOrange.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Passenger Profile Row
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: flisingOrange.withOpacity(0.2),
                          child: Icon(Icons.person, color: flisingOrange, size: 30),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text("Passenger", style: TextStyle(color: Colors.white54, fontSize: 12)),
                              Text("Flising User", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: onlineGreen.withOpacity(0.2), shape: BoxShape.circle),
                          child: Icon(Icons.phone, color: onlineGreen, size: 22),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Route Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Row(children: [const Icon(Icons.my_location, color: Colors.blueAccent, size: 16), const SizedBox(width: 10), Expanded(child: Text(_passengerPickup, style: const TextStyle(color: Colors.white, fontSize: 13)))]),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(color: Colors.white24, height: 1)),
                          Row(children: [Icon(Icons.location_on, color: flisingOrange, size: 16), const SizedBox(width: 10), Expanded(child: Text(_passengerDropoff, style: const TextStyle(color: Colors.white, fontSize: 13)))]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Dynamic Action Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_activeRideStatus == 'ACCEPTED') {
                            _updateMeter('IN_PROGRESS');
                          } else if (_activeRideStatus == 'IN_PROGRESS') {
                            _updateMeter('COMPLETED');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _activeRideStatus == 'ACCEPTED' ? flisingOrange : onlineGreen,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text(
                          _activeRideStatus == 'ACCEPTED' ? 'PICKUP PASSENGER' : 'END RIDE & COLLECT FARE',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),

      // Premium Bottom Navigation (Hidden during active rides)
      bottomNavigationBar: _activeRideStatus == 'IDLE' 
        ? Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10, width: 1))),
            child: BottomNavigationBar(
              backgroundColor: Colors.black,
              selectedItemColor: flisingOrange,
              unselectedItemColor: Colors.white54,
              currentIndex: selectedView,
              onTap: (index) { setState(() { selectedView = index; }); },
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet), label: 'Earnings'),
                BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Live Map'),
                BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
              ],
            ),
          )
        : null,
    );
  }
}