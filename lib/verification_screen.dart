import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb; // <-- The Anti-Crash Magic

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final ImagePicker _picker = ImagePicker();
  
  XFile? _licenseImage;
  XFile? _profileImage;
  XFile? _carImage;

  bool _isSubmitting = false;

  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);
  final Color successGreen = const Color(0xFF4CAF50);

  Future<void> _pickImage(String type) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image != null) {
      setState(() {
        if (type == 'license') _licenseImage = image;
        if (type == 'profile') _profileImage = image;
        if (type == 'car') _carImage = image;
      });
    }
  }

  void _handleSubmit() async {
    setState(() { _isSubmitting = true; });

    await Future.delayed(const Duration(milliseconds: 2500));

    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && _profileImage != null) {
      DatabaseReference ref = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
      ).ref().child('drivers/${currentUser.uid}/profile');
      
      await ref.update({'photoUrl': _profileImage!.path});
    }

    if (!mounted) return;
    setState(() { _isSubmitting = false; });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Documents Verified! Profile updated.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    bool canSubmit = _licenseImage != null && _profileImage != null && _carImage != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text('Driver Verification', style: TextStyle(color: flisingOrange, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        iconTheme: IconThemeData(color: flisingOrange),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Upload Documents', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('We need to verify your identity and vehicle before you can accept rides.', style: TextStyle(color: Colors.white54, fontSize: 15, height: 1.4)),
            const SizedBox(height: 35),

            _buildUploadCard(
              title: "Driver's license",
              subtitle: '(class 3 or 6)',
              icon: Icons.card_membership,
              file: _licenseImage,
              onTap: () => _pickImage('license'),
            ),
            const SizedBox(height: 16),
            
            _buildUploadCard(
              title: 'Profile photo',
              subtitle: 'Clear photo of your face',
              icon: Icons.face,
              file: _profileImage,
              onTap: () => _pickImage('profile'),
            ),
            const SizedBox(height: 16),
            
            _buildUploadCard(
              title: 'Vehicle Photo',
              subtitle: 'Clear photo showing license plate',
              icon: Icons.directions_car_outlined,
              file: _carImage,
              onTap: () => _pickImage('car'),
            ),
            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: (canSubmit && !_isSubmitting) ? _handleSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: flisingOrange,
                disabledBackgroundColor: darkSurface, 
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: canSubmit ? Colors.transparent : Colors.white10),
                ),
                elevation: canSubmit ? 5 : 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : Text(
                      'SUBMIT DOCUMENTS',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: canSubmit ? Colors.white : Colors.white30),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadCard({required String title, required String subtitle, required IconData icon, required XFile? file, required VoidCallback onTap}) {
    bool isUploaded = file != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isUploaded ? successGreen.withOpacity(0.5) : Colors.white10, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                // FIXED: Checks if it's Web or Mobile before loading the image!
                image: isUploaded 
                    ? DecorationImage(
                        image: kIsWeb 
                          ? NetworkImage(file.path) 
                          : FileImage(File(file.path)) as ImageProvider, 
                        fit: BoxFit.cover) 
                    : null,
              ),
              child: isUploaded ? null : Icon(icon, color: flisingOrange, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(isUploaded ? 'Photo attached' : subtitle, style: TextStyle(color: isUploaded ? successGreen : Colors.white54, fontSize: 13, fontWeight: isUploaded ? FontWeight.bold : FontWeight.normal)),
                ],
              ),
            ),
            Icon(isUploaded ? Icons.check_circle : Icons.upload_file, color: isUploaded ? successGreen : Colors.white30, size: 26),
          ],
        ),
      ),
    );
  }
}