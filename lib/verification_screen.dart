import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Color darkSurface = const Color(0xFF1C1C1E);
  final Color flisingOrange = const Color(0xFFE9692C);
  final Color successGreen = const Color(0xFF4CAF50);
  final Color warningRed = const Color(0xFFD32F2F);
  final ImagePicker _picker = ImagePicker();

  File? _profileFile;
  File? _licenseFile;
  File? _vehicleFile;

  String? _profileUrl;
  String? _licenseUrl;
  String? _vehicleUrl;

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isPending = false;
  bool _isVerified = false;

  late DatabaseReference _driverRef;

  @override
  void initState() {
    super.initState();
    _driverRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref('drivers/${_auth.currentUser!.uid}');
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final snap = await _driverRef.get();
      if (snap.exists && mounted) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        final profile = Map<String, dynamic>.from(data['profile'] ?? {});
        setState(() {
          _profileUrl = profile['profileImageUrl'];
          _licenseUrl = profile['licenseImageUrl'];
          _vehicleUrl = profile['vehicleImageUrl'];
          _isPending = profile['pendingApproval'] ?? false;
          _isVerified = profile['isVerified'] ?? false;
        });
      }
    } catch (e) {
      _showSnack('Failed to load: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(String slot) async {
    if (_isPending || _isVerified) return;
    try {
      final f = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 75);
      if (f != null && mounted) {
        setState(() {
          if (slot == 'profile') {
            _profileFile = File(f.path);
            _profileUrl = null;
          } else if (slot == 'license') {
            _licenseFile = File(f.path);
            _licenseUrl = null;
          } else {
            _vehicleFile = File(f.path);
            _vehicleUrl = null;
          }
        });
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<String> _uploadFile(File file, String path) async {
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  Future<void> _submitDocuments() async {
    final uid = _auth.currentUser!.uid;
    setState(() => _isSubmitting = true);

    try {
      final updates = <String, dynamic>{};

      if (_profileFile != null) {
        final url = await _uploadFile(
            _profileFile!, 'driver_docs/$uid/profile.jpg');
        updates['profile/profileImageUrl'] = url;
        setState(() { _profileUrl = url; _profileFile = null; });
      }
      if (_licenseFile != null) {
        final url = await _uploadFile(
            _licenseFile!, 'driver_docs/$uid/license.jpg');
        updates['profile/licenseImageUrl'] = url;
        setState(() { _licenseUrl = url; _licenseFile = null; });
      }
      if (_vehicleFile != null) {
        final url = await _uploadFile(
            _vehicleFile!, 'driver_docs/$uid/vehicle.jpg');
        updates['profile/vehicleImageUrl'] = url;
        setState(() { _vehicleUrl = url; _vehicleFile = null; });
      }

      updates['profile/pendingApproval'] = true;
      await _driverRef.update(updates);
      setState(() => _isPending = true);

      _showSnack('Submitted! We will email you once approved.', isError: false);
    } catch (e) {
      _showSnack('Upload failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? warningRed : successGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        (_profileFile != null || _profileUrl != null) &&
        (_licenseFile != null || _licenseUrl != null) &&
        (_vehicleFile != null || _vehicleUrl != null) &&
        !_isPending &&
        !_isVerified;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Verification',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildStatusBanner(),
                  const SizedBox(height: 30),

                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Required Documents',
                        style: TextStyle(color: Colors.white54, fontSize: 14)),
                  ),
                  const SizedBox(height: 15),

                  _buildDocTile(
                    icon: Icons.account_circle_outlined,
                    title: 'Profile Photo',
                    subtitle: 'Clear photo of your face',
                    slot: 'profile',
                    localFile: _profileFile,
                    networkUrl: _profileUrl,
                  ),
                  const SizedBox(height: 12),
                  _buildDocTile(
                    icon: Icons.credit_card,
                    title: "Driver's License",
                    subtitle: 'Front of your license',
                    slot: 'license',
                    localFile: _licenseFile,
                    networkUrl: _licenseUrl,
                  ),
                  const SizedBox(height: 12),
                  _buildDocTile(
                    icon: Icons.directions_car_outlined,
                    title: 'Vehicle Photo',
                    subtitle: 'Clear photo of your vehicle',
                    slot: 'vehicle',
                    localFile: _vehicleFile,
                    networkUrl: _vehicleUrl,
                  ),
                  const SizedBox(height: 40),

                  if (!_isPending && !_isVerified)
                    ElevatedButton(
                      onPressed: canSubmit
                          ? (_isSubmitting ? null : _submitDocuments)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: flisingOrange,
                        disabledBackgroundColor: darkSurface,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('SUBMIT FOR REVIEW',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner() {
    final color = _isVerified
        ? successGreen
        : _isPending
            ? Colors.orange
            : warningRed;
    final icon = _isVerified
        ? Icons.verified_user
        : _isPending
            ? Icons.hourglass_top
            : Icons.gpp_maybe;
    final title = _isVerified
        ? 'VERIFIED'
        : _isPending
            ? 'UNDER REVIEW'
            : 'ACTION REQUIRED';
    final subtitle = _isVerified
        ? 'You are approved! Go Online and start accepting rides.'
        : _isPending
            ? 'Documents are under review. We will email you once approved.'
            : 'Upload all 3 documents below to start driving.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 48),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }

  Widget _buildDocTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String slot,
    File? localFile,
    String? networkUrl,
  }) {
    final hasImage = localFile != null || networkUrl != null;
    ImageProvider? imageProvider;
    if (localFile != null) imageProvider = FileImage(localFile);
    else if (networkUrl != null) imageProvider = NetworkImage(networkUrl);

    return Container(
      decoration: BoxDecoration(
          color: darkSurface, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
            image: hasImage
                ? DecorationImage(image: imageProvider!, fit: BoxFit.cover)
                : null,
          ),
          child: hasImage ? null : Icon(icon, color: Colors.white54),
        ),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500)),
        subtitle: Text(
          _isVerified
              ? 'Locked — Verified'
              : _isPending
                  ? 'Submitted'
                  : hasImage
                      ? 'Ready to upload'
                      : subtitle,
          style: TextStyle(
            fontSize: 12,
            color: _isVerified
                ? successGreen
                : _isPending
                    ? Colors.orange
                    : hasImage
                        ? successGreen
                        : Colors.white38,
          ),
        ),
        trailing: (_isPending || _isVerified)
            ? Icon(
                _isVerified ? Icons.lock : Icons.hourglass_top,
                color: _isVerified ? successGreen : Colors.orange,
              )
            : ElevatedButton(
                onPressed: () => _pickImage(slot),
                style: ElevatedButton.styleFrom(
                  backgroundColor: flisingOrange,
                  minimumSize: const Size(76, 34),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(hasImage ? 'CHANGE' : 'UPLOAD',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12)),
              ),
      ),
    );
  }
}
