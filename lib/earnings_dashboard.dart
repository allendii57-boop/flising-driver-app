import 'package:flutter/material.dart';

class EarningsDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. COMPACT SUMMARY CARDS
        _buildSummaryCard("TODAY", 125.50),
        _buildSummaryCard("THIS WEEK", 680.00),

        const SizedBox(height: 15),

        // 2. RECENT TRIPS HEADER
        const Text(
          "RECENT TRIPS",
          style: TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        const SizedBox(height: 10),

        // 3. THE SCROLLABLE HISTORY LIST (Takes up remaining space!)
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 0),
            children: [
              _buildTripTile("Today, 2:30 PM", "Completed", 15.00, Colors.green),
              _buildTripTile("Today, 1:15 PM", "Cancelled", 0.00, Colors.red),
              _buildTripTile("Today, 10:45 AM", "Completed", 22.50, Colors.green),
              _buildTripTile("Yesterday, 4:00 PM", "Ignored", 0.00, Colors.grey),
              _buildTripTile("Yesterday, 2:10 PM", "Completed", 18.00, Colors.green),
              _buildTripTile("Yesterday, 11:00 AM", "Completed", 25.00, Colors.green),
              _buildTripTile("Monday, 9:30 AM", "Completed", 12.50, Colors.green),
            ],
          ),
        ),
        
        // Adds a little extra space at the bottom so the list doesn't get hidden behind the bottom nav bar
        const SizedBox(height: 60), 
      ],
    );
  }

  // Reusable compact card builder
  Widget _buildSummaryCard(String title, double totalFares) {
    double fee = totalFares * 0.20; // Auto-calculates the 20% platform cut
    double earnings = totalFares - fee;

    return Container(
      margin: const EdgeInsets.only(bottom: 10), // Tighter margin between cards
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), // Tighter padding inside
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total Fares", style: TextStyle(color: Colors.white, fontSize: 13)), 
              Text("\$${totalFares.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 13))
            ],
          ),
          const SizedBox(height: 4), // Tighter spacing
                    Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Changed from red to orange, and you can tweak the wording here!
              const Text("Platform Share (20%)", style: TextStyle(color: Colors.orange, fontSize: 13)), 
              
              // Removed the '-' sign and changed to orange
              Text("\$${fee.toStringAsFixed(2)}", style: const TextStyle(color: Colors.orange, fontSize: 13)) 
            ],
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Your Earnings", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), 
              Text("\$${earnings.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15))
            ],
          ),
        ],
      ),
    );
  }

  // Reusable trip tile builder
  Widget _buildTripTile(String time, String status, double amount, Color statusColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey[850]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(time, style: const TextStyle(color: Colors.white, fontSize: 13)),
              const SizedBox(height: 4),
              Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          Text(
            amount > 0 ? "+\$${amount.toStringAsFixed(2)}" : "\$0.00",
            style: TextStyle(
              color: amount > 0 ? Colors.white : Colors.grey[600],
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}