import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

const Color _orange = Color(0xFFE9692C);
const Color _dark = Color(0xFF1C1C1E);
const Color _green = Color(0xFF2E7D32);

void showFlisingRateCard(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _dark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _orange, width: 1.5),
      ),
      title: const Row(
        children: [
          Icon(Icons.receipt_long, color: _orange),
          SizedBox(width: 10),
          Text('OFFICIAL RATE CARD', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _rateItem(Icons.directions_car, 'Car Ride', 'K 6.70 / km'),
          const SizedBox(height: 8),
          _rateItem(Icons.two_wheeler, 'Motorcycle', 'K 5.50 / km'),
          const SizedBox(height: 8),
          _rateItem(Icons.inventory_2, 'Parcel Delivery', 'K 5.00 / km'),
          const SizedBox(height: 12),
          const Text(
            '• Calculated by exact OSRM road distance.\n• Rounded to nearest 10 toea (K 0.10).\n• Flising Platform Share: 10%.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(backgroundColor: _orange),
          child: const Text('CLOSE', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

Widget _rateItem(IconData icon, String title, String rate) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
    child: Row(
      children: [
        Icon(icon, color: _orange),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        Text(rate, style: const TextStyle(color: _green, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

void showFlisingStreetHail({
  required BuildContext context,
  required void Function(String rideId, String pName, String dropName) onRideStarted,
}) {
  final presets = >[
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
  String vehicle = 'Car';
  Map<String, dynamic> dest = presets[0];
  double oLat = -2.6741, oLng = 141.3028, km = 1.5;
  String fare = 'Calculating...';
  bool busy = false, init = false;

  Future<void> calc(StateSetter setD) async {
    setD(() => busy = true);
    try {
      final p = await Geolocator.getCurrentPosition();
      oLat = p.latitude; oLng = p.longitude;
    } catch (_) {}
    final dLat = (dest['lat'] as num).toDouble(), dLng = (dest['lng'] as num).toDouble();
    try {
      final r = await http.get(Uri.parse('https://router.project-osrm.org/route/v1/driving/$oLng,$oLat;$dLng,$dLat?overview=false'));
      final d = json.decode(r.body);
      if (d['code'] == 'Ok') km = ((d['routes'][0]['distance'] as num).toDouble() / 1000.0).clamp(0.5, 200.0);
    } catch (_) {}
    final total = ((km * (vehicle == 'Car' ? 6.70 : 5.50)) * 10).round() / 10.0;
    setD(() { busy = false; fare = 'K ' + total.toStringAsFixed(2); });
  }

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (sCtx, setD) {
        if (!init) { init = true; Future.microtask(() => calc(setD)); }
        return AlertDialog(
          backgroundColor: _dark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _orange)),
          title: const Text('STREET HAIL RIDE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: ChoiceChip(label: const Text('Car'), selected: vehicle == 'Car', selectedColor: _orange, onSelected: (_) { vehicle = 'Car'; calc(setD); })),
                    const SizedBox(width: 8),
                    Expanded(child: ChoiceChip(label: const Text('Bike'), selected: vehicle == 'Motorcycle', selectedColor: _orange, onSelected: (_) { vehicle = 'Motorcycle'; calc(setD); })),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButton<String>(
                  value: dest['name'] as String,
                  dropdownColor: _dark,
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white),
                  items: presets.map((p) => DropdownMenuItem(value: p['name'] as String, child: Text(p['name'] as String))).toList(),
                  onChanged: (v) { dest = presets.firstWhere((e) => e['name'] == v); calc(setD); },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passengerCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: 'Passenger Name/Phone (Optional)', hintStyle: TextStyle(color: Colors.white38)),
                ),
                const SizedBox(height: 12),
                Text('Distance: ' + km.toStringAsFixed(1) + ' km', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Text(busy ? 'Calculating...' : fare, style: const TextStyle(color: _green, fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _orange),
              onPressed: busy ? null : () async {
                final u = FirebaseAuth.instance.currentUser;
                if (u == null) return;
                final db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app').ref();
                final ref = db.child('rides').push();
                final pName = passengerCtrl.text.trim().isEmpty ? 'Street-Hail Passenger' : passengerCtrl.text.trim();
                final dName = dest['name'].toString();
                await ref.set({
                  'passengerId': 'street_hail',
                  'passengerName': pName,
                  'assignedDriverId': u.uid,
                  'driverName': u.displayName ?? 'Flising Driver',
                  'pickupText': 'Street Hail (Current GPS)',
                  'dropoffText': dName,
                  'pickupLat': oLat,
                  'pickupLng': oLng,
                  'dropoffLat': (dest['lat'] as num).toDouble(),
                  'dropoffLng': (dest['lng'] as num).toDouble(),
                  'fare': fare,
                  'vehicleType': vehicle,
                  'paymentMethod': 'CASH',
                  'type': 'street_hail',
                  'status': 'IN_PROGRESS',
                  'timestamp': ServerValue.timestamp,
                });
                await db.child('drivers/' + u.uid + '/currentRideId').set(ref.key!);
                Navigator.pop(ctx);
                onRideStarted(ref.key!, pName, dName);
              },
              child: const Text('START', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    ),
  );
}
