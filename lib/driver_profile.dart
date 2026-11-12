import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import 'verification_screen.dart';
import 'splash_screen.dart';

class DriverProfile extends StatefulWidget {
  const DriverProfile({super.key});

  @override
  State<DriverProfile> createState() => _DriverProfileState();
}

class _DriverProfileState extends State<DriverProfile> {
  String _displayName = "Loading...";
  String _profilePhotoPath = "";
  String _licensePhotoPath = "";
  String _vehiclePhotoPath = "";
  String _carModel = "Not submitted";
  String _plateNumber = "Not submitted";
  String _phoneNumber = "";

  double _availableBalance = 0.0;
  StreamSubscription<DatabaseEvent>? _walletListener;
  StreamSubscription<DatabaseEvent>? _profileListener;

  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);
  final Color successGreen = const Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    _listenToProfileData();
    _listenToWalletBalance();
  }

  @override
  void dispose() {
    _walletListener?.cancel();
    _profileListener?.cancel();
    super.dispose();
  }

  void _listenToProfileData() {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    DatabaseReference ref = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref().child('drivers/${currentUser.uid}/profile');

    _profileListener = ref.onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _displayName = (data['fullName'] ?? currentUser.displayName ?? "Driver").toString();
          _profilePhotoPath = (data['profileImageUrl'] ?? "").toString();
          _licensePhotoPath = (data['licenseImageUrl'] ?? "").toString();
          _vehiclePhotoPath = (data['vehicleImageUrl'] ?? "").toString();
          _carModel = (data['carModel'] != null && data['carModel'].toString().isNotEmpty)
              ? data['carModel'].toString()
              : "Not submitted";
          _plateNumber = (data['plateNumber'] != null && data['plateNumber'].toString().isNotEmpty)
              ? data['plateNumber'].toString()
              : "Not submitted";
          _phoneNumber = (data['phoneNumber'] ?? data['phone'] ?? "").toString();
        });
      }
    });
  }

  void _listenToWalletBalance() {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _walletListener = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref().child('rides').orderByChild('assignedDriverId').equalTo(currentUser.uid).onValue.listen((event) {
      if (!mounted) return;
      double calculatedBalance = 0.0;
      if (event.snapshot.exists && event.snapshot.value is Map) {
        Map<dynamic, dynamic> ridesData = event.snapshot.value as Map<dynamic, dynamic>;
        ridesData.forEach((key, value) {
          if (value is Map && value['status'] == 'COMPLETED' && value['payoutStatus'] == null) {
            String fareStr = value['fare']?.toString() ?? "K 0.00";
            fareStr = fareStr.replaceAll(RegExp(r'[^0-9.]'), '');
            double grossFare = double.tryParse(fareStr) ?? 0.0;
            calculatedBalance += (grossFare * 0.90);
          }
        });
      }
      setState(() => _availableBalance = calculatedBalance);
    });
  }

  Future<void> _launchWhatsApp() async {
    const message = "Hi Flising Support, I need help with my Driver app.";
    final Uri whatsappUri = Uri.parse("https://wa.me/67584171054?text=${Uri.encodeComponent(message)}");
    try {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _previewImage(String title, String url) {
    if (url.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(url, height: 260, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("CLOSE", style: TextStyle(color: flisingOrange, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    String email = user?.email ?? "driver@flising.com";
    bool hasProfilePhoto = _profilePhotoPath.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _previewImage("Profile Photo", _profilePhotoPath),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: flisingOrange, width: 3),
                    boxShadow: [BoxShadow(color: flisingOrange.withOpacity(0.3), blurRadius: 15, spreadRadius: 5)],
                    image: hasProfilePhoto
                        ? DecorationImage(image: NetworkImage(_profilePhotoPath), fit: BoxFit.cover)
                        : null,
                  ),
                  child: hasProfilePhoto ? null : Icon(Icons.person, size: 70, color: darkSurface),
                ),
              ),
              const SizedBox(height: 14),
              Text(_displayName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(email, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              if (_phoneNumber.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(_phoneNumber, style: TextStyle(color: flisingOrange, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: darkSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("SUBMITTED VEHICLE & DOCUMENTS",
                            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const VerificationScreen(initialChangeCarMode: true),
                            ));
                          },
                          icon: Icon(Icons.edit, color: flisingOrange, size: 15),
                          label: Text("Change Car", style: TextStyle(color: flisingOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.directions_car, color: flisingOrange, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text("Car Model: $_carModel", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.pin_outlined, color: flisingOrange, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text("Plate Number: $_plateNumber", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _docThumb("Licence", _licensePhotoPath, Icons.credit_card)),
                        const SizedBox(width: 12),
                        Expanded(child: _docThumb("Car Photo", _vehiclePhotoPath, Icons.directions_car)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen()));
                  },
                  icon: Icon(Icons.verified_user, color: flisingOrange),
                  label: Text("VERIFICATION PORTAL", style: TextStyle(color: flisingOrange, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: flisingOrange.withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: flisingOrange, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE9692C), Color(0xFFB34B19)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: flisingOrange.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("AVAILABLE WALLET BALANCE",
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    Text("K ${_availableBalance.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildMenuOption(
                icon: Icons.directions_car_outlined,
                title: "Change / Update Vehicle",
                subtitle: "Submit new car photo, model & plate number",
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const VerificationScreen(initialChangeCarMode: true),
                  ));
                },
              ),
              _buildMenuOption(
                icon: Icons.help_outline,
                title: "Driver Support",
                subtitle: "Chat with us on WhatsApp",
                onTap: _launchWhatsApp,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!context.mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const SplashScreen()),
                      (Route<dynamic> route) => false,
                    );
                  },
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  label: const Text("SIGN OUT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.redAccent, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _docThumb(String label, String url, IconData fallbackIcon) {
    final hasImg = url.isNotEmpty;
    return GestureDetector(
      onTap: hasImg ? () => _previewImage(label, url) : null,
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
          image: hasImg ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
        ),
        child: Container(
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [Colors.black.withOpacity(0.8), Colors.transparent],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
          child: Row(
            children: [
              Icon(fallbackIcon, color: flisingOrange, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasImg ? label : "$label (None)",
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuOption({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: darkSurface, borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: flisingOrange),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 16),
        onTap: onTap,
      ),
    );
  }
}
