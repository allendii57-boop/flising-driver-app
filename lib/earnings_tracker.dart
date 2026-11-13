import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class EarningsTracker extends StatelessWidget {
  const EarningsTracker({super.key});

  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);
  final Color successGreen = const Color(0xFF4CAF50);

  String _formatDateTime(dynamic ts) {
    if (ts is! num) return 'Unknown Date & Time';
    final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hr = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}, ${d.year} • $hr:$min $ampm';
  }

  void _showDriverTripModal(BuildContext context, Map ride, String dateTimeStr, double gross) {
    final pickup = (ride['pickupText'] ?? 'Current Location').toString();
    final dropoff = (ride['dropoffText'] ?? 'Unknown Dropoff').toString();
    final passenger = (ride['passengerName'] ?? 'Passenger').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(dateTimeStr, style: TextStyle(color: flisingOrange, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From: $pickup', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            Text('To: $dropoff', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Passenger: $passenger', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Divider(color: Colors.white12, height: 22),
            Text('Total Fare: K ${gross.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 14)),
            Text('Flising Share (10%): K ${(gross * 0.10).toStringAsFixed(2)}', style: TextStyle(color: flisingOrange, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Your Net (90%): K ${(gross * 0.90).toStringAsFixed(2)}', style: TextStyle(color: successGreen, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: flisingOrange),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Earnings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 14),
              Expanded(
                child: currentUser == null
                    ? const Center(child: Text('Log in to see earnings', style: TextStyle(color: Colors.white54)))
                    : StreamBuilder(
                        stream: dbRef.child('rides').orderByChild('assignedDriverId').equalTo(currentUser.uid).onValue,
                        builder: (context, AsyncSnapshot snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator(color: flisingOrange));
                          }
                          final List completedRides = [];
                          final List<String> unsettledRideIds = [];
                          double unsettledGross = 0.0;
                          bool isPendingSettlement = false;
                          final List<String> unsettledRideIds = [];
                          double unsettledGross = 0.0;
                          bool isPendingSettlement = false;
                          double todayGross = 0.0;
                          double weekGross = 0.0;
                          double twoWeekGross = 0.0;
                          double monthGross = 0.0;
                          double allTimeGross = 0.0;
                          final now = DateTime.now();
                          final cut7 = now.subtract(const Duration(days: 7));
                          final cut14 = now.subtract(const Duration(days: 14));
                          final cut30 = now.subtract(const Duration(days: 30));

                          if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
                            final ridesData = snapshot.data!.snapshot.value as Map;
                            ridesData.forEach((key, value) {
                              if (value is Map && value['status'] == 'COMPLETED') {
                                completedRides.add(value);
                                final fareStr = (value['fare'] ?? '0').toString().replaceAll(RegExp(r'[^0-9.]'), '');
                                final fareAmount = double.tryParse(fareStr) ?? 0.0;
                                allTimeGross += fareAmount;
                                if (value['payoutStatus'] != 'PAID') {
                                  unsettledGross += fareAmount;
                                  unsettledRideIds.add(key.toString());
                                  if (value['payoutStatus'] == 'PENDING_SETTLEMENT') isPendingSettlement = true;
                                }
                                if (value['payoutStatus'] != 'PAID') {
                                  unsettledGross += fareAmount;
                                  unsettledRideIds.add(key.toString());
                                  if (value['payoutStatus'] == 'PENDING_SETTLEMENT') {
                                    isPendingSettlement = true;
                                  }
                                }
                                if (value['timestamp'] is num) {
                                  final rideDate = DateTime.fromMillisecondsSinceEpoch((value['timestamp'] as num).toInt());
                                  if (rideDate.year == now.year && rideDate.month == now.month && rideDate.day == now.day) {
                                    todayGross += fareAmount;
                                  }
                                  if (rideDate.isAfter(cut7)) weekGross += fareAmount;
                                  if (rideDate.isAfter(cut14)) twoWeekGross += fareAmount;
                                  if (rideDate.isAfter(cut30)) monthGross += fareAmount;
                                }
                              }
                            });
                          }
                          completedRides.sort((a, b) => (((b as Map)['timestamp'] ?? 0) as num).compareTo(((a as Map)['timestamp'] ?? 0) as num));
                          final flisingShare10 = unsettledGross * 0.10;

                          void showFullBreakdown() {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: darkSurface,
                                title: const Text('Full Earnings Breakdown', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Weekly (7d) Net: K ${(weekGross * 0.9).toStringAsFixed(2)} (Flising Share 10%: K ${(weekGross * 0.1).toStringAsFixed(2)})', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                    const SizedBox(height: 8),
                                    Text('2 Weeks (14d) Net: K ${(twoWeekGross * 0.9).toStringAsFixed(2)} (Flising Share 10%: K ${(twoWeekGross * 0.1).toStringAsFixed(2)})', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                    const SizedBox(height: 8),
                                    Text('Monthly (30d) Net: K ${(monthGross * 0.9).toStringAsFixed(2)} (Flising Share 10%: K ${(monthGross * 0.1).toStringAsFixed(2)})', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                    const Divider(color: Colors.white12, height: 20),
                                    Text('All-Time Gross: K ${allTimeGross.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    Text('All-Time Net (90%): K ${(allTimeGross * 0.9).toStringAsFixed(2)}', style: TextStyle(color: successGreen, fontWeight: FontWeight.bold)),
                                    Text('Flising Share (10%): K ${(allTimeGross * 0.1).toStringAsFixed(2)}', style: TextStyle(color: flisingOrange, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CLOSE', style: TextStyle(color: flisingOrange))),
                                ],
                              ),
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Flising Share (10%) Settlement Card
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: darkSurface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: flisingOrange, width: 1.4),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('FLISING SHARE (10%)', style: TextStyle(color: flisingOrange, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                                          const SizedBox(height: 4),
                                          Text('K ${flisingShare10.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                                          Text('From K ${unsettledGross.toStringAsFixed(2)} unsettled fares', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: flisingShare10 <= 0
                                            ? Colors.white12
                                            : (isPendingSettlement ? Colors.amber.shade800 : flisingOrange),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: (flisingShare10 <= 0 || isPendingSettlement)
                                          ? null
                                          : () async {
                                              for (final rId in unsettledRideIds) {
                                                await dbRef.child('rides/$rId').update({'payoutStatus': 'PENDING_SETTLEMENT'});
                                              }
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Flising Share marked as Pending Admin Settlement!')),
                                                );
                                              }
                                            },
                                      child: Text(
                                        flisingShare10 <= 0
                                            ? 'SETTLED'
                                            : (isPendingSettlement ? 'PENDING...' : 'FLISING SHARE 10%'),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: darkSurface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: flisingOrange, width: 1.4),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('FLISING SHARE 10%', style: TextStyle(color: flisingOrange, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                                          const SizedBox(height: 4),
                                          Text('K ${(unsettledGross * 0.10).toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                                          Text('From K ${unsettledGross.toStringAsFixed(2)} unsettled fares', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: unsettledGross <= 0 ? Colors.white12 : (isPendingSettlement ? Colors.amber.shade800 : flisingOrange),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: (unsettledGross <= 0 || isPendingSettlement)
                                          ? null
                                          : () async {
                                              final db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app').ref();
                                              for (final rId in unsettledRideIds) {
                                                await db.child('rides/$rId').update({'payoutStatus': 'PENDING_SETTLEMENT'});
                                              }
                                            },
                                      child: Text(
                                        unsettledGross <= 0 ? 'SETTLED' : (isPendingSettlement ? 'PENDING...' : 'FLISING SHARE 10%'),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(onTap: showFullBreakdown, child: _buildEarningsCard('TODAY (TAP FOR FULL BREAKDOWN)', todayGross, true)),
                              const SizedBox(height: 10),
                              GestureDetector(onTap: showFullBreakdown, child: _buildEarningsCard('THIS WEEK (LAST 7 DAYS)', weekGross, false)),
                              const SizedBox(height: 14),
                              Text('Completed Rides (${completedRides.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 8),
                              Expanded(
                                child: completedRides.isEmpty
                                    ? const Center(child: Text('No completed rides yet.', style: TextStyle(color: Colors.white30)))
                                    : ListView.builder(
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: completedRides.length,
                                        itemBuilder: (context, index) {
                                          final ride = completedRides[index] as Map;
                                          final pickup = (ride['pickupText'] ?? 'Current Location').toString();
                                          final destination = (ride['dropoffText'] ?? 'Unknown Dropoff').toString();
                                          final fareStr = (ride['fare'] ?? '0').toString().replaceAll(RegExp(r'[^0-9.]'), '');
                                          final grossFare = double.tryParse(fareStr) ?? 0.0;
                                          final netFare = grossFare * 0.90;
                                          final dateTimeText = _formatDateTime(ride['timestamp']);
                                          return GestureDetector(
                                            onTap: () => _showDriverTripModal(context, ride, dateTimeText, grossFare),
                                            child: _buildTripRow(pickup, destination, netFare.toStringAsFixed(2), dateTimeText),
                                          );
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

  Widget _buildEarningsCard(String title, double gross, bool isMain) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isMain ? flisingOrange.withOpacity(0.5) : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: flisingOrange, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          _rowItem('Total Fare Collected', 'K ${gross.toStringAsFixed(2)}', Colors.white70, successGreen),
          const SizedBox(height: 4),
          _rowItem('Flising Share (10%)', 'K ${(gross * 0.10).toStringAsFixed(2)}', Colors.white70, flisingOrange),
          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(color: Colors.white10)),
          _rowItem('Your Net Earnings', 'K ${(gross * 0.90).toStringAsFixed(2)}', Colors.white, successGreen, isBig: true),
        ],
      ),
    );
  }

  Widget _rowItem(String label, String value, Color labelColor, Color valueColor, {bool isBig = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: isBig ? 15 : 13)),
        Text(value, style: TextStyle(color: valueColor, fontSize: isBig ? 22 : 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTripRow(String pickup, String destination, String amount, String dateTime) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateTime, style: TextStyle(color: flisingOrange, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('From: $pickup', style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('To: $destination', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('K $amount', style: TextStyle(color: successGreen, fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
