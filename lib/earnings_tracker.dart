import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class EarningsTracker extends StatelessWidget {
  const EarningsTracker({super.key});

  // Premium Theme Colors
  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);
  final Color successGreen = const Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Earnings",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 20),

              Expanded(
                child: currentUser == null
                    ? const Center(child: Text("Log in to see earnings", style: TextStyle(color: Colors.white54)))
                    : StreamBuilder<DatabaseEvent>(
                        stream: FirebaseDatabase.instanceFor(
                          app: Firebase.app(),
                          databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
                        ).ref().child('rides').orderByChild('assignedDriverId').equalTo(currentUser.uid).onValue,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator(color: flisingOrange));
                          }
                          
                          List<Map<dynamic, dynamic>> completedRides = [];
                          double todayGross = 0.0;
                          double weekGross = 0.0;
                          DateTime now = DateTime.now();

                          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                            Map<dynamic, dynamic> ridesData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                            ridesData.forEach((key, value) {
                              if (value['status'] == 'COMPLETED') {
                                completedRides.add(value);
                                
                                // Logic for cleaning currency string and calculating totals
                                String fareStr = value['fare']?.toString() ?? "K 0.00";
                                fareStr = fareStr.replaceAll(RegExp(r'[^0-9.]'), '');
                                double fareAmount = double.tryParse(fareStr) ?? 0.0;
                                // BEFORE (lines 60-67):
weekGross += fareAmount;

if (value['timestamp'] != null) {
  DateTime rideDate = DateTime.fromMillisecondsSinceEpoch(value['timestamp']);
  if (rideDate.year == now.year && rideDate.month == now.month && rideDate.day == now.day) {
    todayGross += fareAmount;
  }
}

// AFTER:
if (value['timestamp'] != null) {
  DateTime rideDate = DateTime.fromMillisecondsSinceEpoch(value['timestamp']);

  // Today check
  if (rideDate.year == now.year &&
      rideDate.month == now.month &&
      rideDate.day == now.day) {
    todayGross += fareAmount;
  }

  // This week check
  DateTime startOfWeek = now.subtract(Duration(days: now.weekday % 7));
  DateTime weekStart = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
  if (rideDate.isAfter(weekStart)) {
    weekGross += fareAmount;
  }
}
                              }
                            });
                          }

                          // Sort newest to oldest
                          completedRides.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildEarningsCard("TODAY", todayGross, true),
                              const SizedBox(height: 16),
                              _buildEarningsCard("THIS WEEK", weekGross, false),
                              const SizedBox(height: 24),
                              const Text(
                                "Completed Rides",
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 12),
                              
                              Expanded(
                                child: completedRides.isEmpty
                                    ? const Center(child: Text("No completed rides yet.", style: TextStyle(color: Colors.white30)))
                                    : ListView.builder(
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: completedRides.length,
                                        itemBuilder: (context, index) {
                                          var ride = completedRides[index];
                                          String destination = ride['dropoffText'] ?? "Unknown Dropoff";
                                          
                                          String fareStr = ride['fare']?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? "0.0";
                                          double netFare = (double.tryParse(fareStr) ?? 0.0) * 0.90;
                                          
                                          String timeText = "Unknown Time";
                                          if (ride['timestamp'] != null) {
                                            DateTime date = DateTime.fromMillisecondsSinceEpoch(ride['timestamp']);
                                            timeText = "${date.hour > 12 ? date.hour - 12 : date.hour}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}";
                                          }
                                          return _buildTripRow(destination, netFare.toStringAsFixed(2), timeText);
                                        },
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- PREMIUM UI HELPERS ---

  Widget _buildEarningsCard(String title, double gross, bool isMain) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isMain ? flisingOrange.withOpacity(0.5) : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title, 
            style: TextStyle(color: flisingOrange, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)
          ),
          const SizedBox(height: 12),
          _rowItem("Total Fare Collected", "K ${gross.toStringAsFixed(2)}", Colors.white70, successGreen),
          const SizedBox(height: 4),
          // Correction Applied: Removed minus sign for partnership look
          _rowItem("Flising Share (10%)", "K ${(gross * 0.10).toStringAsFixed(2)}", Colors.white70, flisingOrange),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.white10)),
          _rowItem("Your Net Earnings", "K ${(gross * 0.90).toStringAsFixed(2)}", Colors.white, successGreen, isBig: true),
        ],
      ),
    );
  }

  Widget _rowItem(String label, String value, Color labelColor, Color valueColor, {bool isBig = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: isBig ? 16 : 13)),
        Text(value, style: TextStyle(color: valueColor, fontSize: isBig ? 24 : 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTripRow(String destination, String amount, String time) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: darkSurface, 
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.local_taxi, color: flisingOrange, size: 20),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(destination, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(time, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ],
          ),
          // const removed here to prevent evaluation error
          Text(
            "K $amount", 
            style: TextStyle(color: successGreen, fontSize: 15, fontWeight: FontWeight.bold)
          ),
        ],
      ),
    );
  }
}
