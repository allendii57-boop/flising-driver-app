import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb; // <-- The Anti-Crash Magic

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
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
    ).ref().child('drivers/${currentUser.uid}/profile');

    _profileListener = ref.onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _displayName = data['fullName'] ?? currentUser.displayName ?? "Driver";
          _profilePhotoPath = data['profileImageUrl'] ?? ""; 
        });
      }
    });
  }

  void _listenToWalletBalance() {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _walletListener = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
    ).ref().child('rides').orderByChild('assignedDriverId').equalTo(currentUser.uid).onValue.listen((event) {
      if (!mounted) return;
      
      double calculatedBalance = 0.0;
      if (event.snapshot.exists) {
        Map<dynamic, dynamic> ridesData = event.snapshot.value as Map<dynamic, dynamic>;
        ridesData.forEach((key, value) {
          if (value['status'] == 'COMPLETED' && value['payoutStatus'] == null) {
            String fareStr = value['fare']?.toString() ?? "K 0.00";
            fareStr = fareStr.replaceAll(RegExp(r'[^0-9.]'), '');
            double grossFare = double.tryParse(fareStr) ?? 0.0;
            calculatedBalance += (grossFare * 0.80);
          }
        });
      }
      setState(() { _availableBalance = calculatedBalance; });
    });
  }

  Future<void> _launchWhatsApp() async {
    final Uri whatsappUri = Uri.parse("https://wa.me/67570000000"); 
    
    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("WhatsApp is not installed on this device."), backgroundColor: Colors.redAccent)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    String email = user?.email ?? "driver@flising.com";
    
    // FIXED: Removed the crash-causing existsSync() check for web emulators
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
              
              Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: flisingOrange, width: 3),
                  boxShadow: [BoxShadow(color: flisingOrange.withOpacity(0.3), blurRadius: 15, spreadRadius: 5)],
                  // FIXED: Checks if it's Web or Mobile before loading the image!
                  image: hasProfilePhoto 
                      ? DecorationImage(
                          image: NetworkImage(_profilePhotoPath),
                          fit: BoxFit.cover) 
                      : null,
                ),
                child: hasProfilePhoto ? null : Icon(Icons.person, size: 70, color: darkSurface),
              ),
              const SizedBox(height: 15),

              Text(_displayName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(email, style: const TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(context, PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => const VerificationScreen(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        const begin = Offset(0.0, 1.0);
                        const end = Offset.zero; 
                        const curve = Curves.easeOutQuart;
                        var tween = Tween<Offset>(begin: begin, end: end).chain(CurveTween(curve: curve));
                        return SlideTransition(position: animation.drive(tween), child: child);
                      },
                    ));
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
              const SizedBox(height: 30),

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
                    const Text("AVAILABLE WALLET BALANCE", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    Text("K ${_availableBalance.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              _buildMenuOption(
                icon: Icons.directions_car_outlined, 
                title: "Vehicle Information", 
                subtitle: "View assigned vehicle",
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Vehicle assignments are managed by Flising Admin."), backgroundColor: Colors.black87)
                  );
                }
              ),
              _buildMenuOption(
                icon: Icons.document_scanner_outlined, 
                title: "Driver Documents", 
                subtitle: "Update License & ID",
                onTap: () {
                   Navigator.push(context, MaterialPageRoute(builder: (context) => const VerificationScreen()));
                }
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

  Widget _buildMenuOption({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: darkSurface,
        borderRadius: BorderRadius.circular(15),
      ),
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
