import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class VerificationScreen extends StatefulWidget {
  final bool initialChangeCarMode;
  const VerificationScreen({super.key, this.initialChangeCarMode = false});

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

  final TextEditingController _carModelCtrl = TextEditingController();
  final TextEditingController _plateCtrl = TextEditingController();

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
  bool _isChangingCar = false;

  late DatabaseReference _driverRef;

  @override
  void initState() {
    super.initState();
    _isChangingCar = widget.initialChangeCarMode;
    _driverRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref('drivers/${_auth.currentUser!.uid}');
    _loadData();
  }

  @override
  void dispose() {
    _carModelCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final snap = await _driverRef.get();
      if (snap.exists && mounted) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        final profile = Map<String, dynamic>.from(data['profile'] ?? {});
        setState(() {
          _profileUrl = profile['profileImageUrl']?.toString();
          _licenseUrl = profile['licenseImageUrl']?.toString();
          _vehicleUrl = profile['vehicleImageUrl']?.toString();
          _carModelCtrl.text = (profile['carModel'] ?? '').toString();
          _plateCtrl.text = (profile['plateNumber'] ?? '').toString();
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
    try {
      final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
      if (f != null && mounted) {
        setState(() {
          if (slot == 'profile') {
            _profileFile = File(f.path);
          } else if (slot == 'license') {
            _licenseFile = File(f.path);
          } else {
            _vehicleFile = File(f.path);
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
    final model = _carModelCtrl.text.trim();
    final plate = _plateCtrl.text.trim().toUpperCase();

    if (model.isEmpty || plate.isEmpty) {
      _showSnack('Please enter your Car Model and Plate Number.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final updates = <String, dynamic>{
        'profile/carModel': model,
        'profile/plateNumber': plate,
      };

      if (_profileFile != null) {
        final url = await _uploadFile(_profileFile!, 'driver_docs/$uid/profile.jpg');
        updates['profile/profileImageUrl'] = url;
        setState(() { _profileUrl = url; _profileFile = null; });
      }
      if (_licenseFile != null) {
        final url = await _uploadFile(_licenseFile!, 'driver_docs/$uid/license.jpg');
        updates['profile/licenseImageUrl'] = url;
        setState(() { _licenseUrl = url; _licenseFile = null; });
      }
      if (_vehicleFile != null) {
        final url = await _uploadFile(_vehicleFile!, 'driver_docs/$uid/vehicle_${DateTime.now().millisecondsSinceEpoch}.jpg');
        updates['profile/vehicleImageUrl'] = url;
        setState(() { _vehicleUrl = url; _vehicleFile = null; });
      }

      if (_isChangingCar && _isVerified) {
        updates['profile/vehicleUpdateAt'] = ServerValue.timestamp;
        updates['profile/vehicleChangeSubmitted'] = true;
      } else {
        updates['profile/pendingApproval'] = true;
        setState(() => _isPending = true);
      }

      await _driverRef.update(updates);
      setState(() => _isChangingCar = false);

      _showSnack(
        _isVerified
            ? 'Vehicle details updated successfully!'
            : 'Submitted! We will review and approve your profile.',
        isError: false,
      );
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

  Widget _buildTextField(TextEditingController ctrl, String label, String hint, IconData icon, bool enabled) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: darkSurface, borderRadius: BorderRadius.circular(16)),
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          icon: Icon(icon, color: flisingOrange),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
          border: InputBorder.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canEditAll = !_isPending && !_isVerified;
    final bool canEditVehicle = canEditAll || _isChangingCar;
    final bool canSubmit = canEditVehicle &&
        (_profileFile != null || _profileUrl != null) &&
        (_licenseFile != null || _licenseUrl != null) &&
        (_vehicleFile != null || _vehicleUrl != null);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_isChangingCar ? 'Update Vehicle' : 'Verification Portal', style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusBanner(),
                  const SizedBox(height: 24),
                  if ((_isVerified || _isPending) && !_isChangingCar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _isChangingCar = true),
                          icon: Icon(Icons.directions_car, color: flisingOrange),
                          label: Text('CHANGE VEHICLE / UPDATE CAR DETAILS', style: TextStyle(color: flisingOrange, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: flisingOrange, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  const Text('Driver & Licence Photos', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 10),
                  _buildDocTile(
                    icon: Icons.account_circle_outlined,
                    title: 'Profile Photo',
                    subtitle: 'Clear photo of your face',
                    slot: 'profile',
                    localFile: _profileFile,
                    networkUrl: _profileUrl,
                    editable: canEditAll,
                  ),
                  const SizedBox(height: 12),
                  _buildDocTile(
                    icon: Icons.credit_card,
                    title: "Driver's Licence",
                    subtitle: 'Front of your PNG licence',
                    slot: 'license',
                    localFile: _licenseFile,
                    networkUrl: _licenseUrl,
                    editable: canEditAll,
                  ),
                  const SizedBox(height: 24),
                  const Text('Vehicle Details', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 10),
                  _buildDocTile(
                    icon: Icons.directions_car_outlined,
                    title: 'Car Photo',
                    subtitle: 'Clear photo of your vehicle',
                    slot: 'vehicle',
                    localFile: _vehicleFile,
                    networkUrl: _vehicleUrl,
                    editable: canEditVehicle,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(_carModelCtrl, 'Car Model & Colour', 'e.g. White Toyota Corolla', Icons.directions_car, canEditVehicle),
                  _buildTextField(_plateCtrl, 'Plate Number', 'e.g. BAA 123', Icons.pin_outlined, canEditVehicle),
                  const SizedBox(height: 28),
                  if (canEditVehicle)
                    ElevatedButton(
                      onPressed: canSubmit ? (_isSubmitting ? null : _submitDocuments) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: flisingOrange,
                        disabledBackgroundColor: darkSurface,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(_isChangingCar ? 'SUBMIT NEW VEHICLE DETAILS' : 'SUBMIT FOR REVIEW',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner() {
    final color = _isVerified ? successGreen : (_isPending ? Colors.orange : warningRed);
    final icon = _isVerified ? Icons.verified_user : (_isPending ? Icons.hourglass_top : Icons.gpp_maybe);
    final title = _isVerified ? 'VERIFIED' : (_isPending ? 'UNDER REVIEW' : 'ACTION REQUIRED');
    final subtitle = _isVerified
        ? 'You are approved! If you change your car, tap "Change Vehicle" below to submit your new car photo, model, and plate number.'
        : _isPending
            ? 'Documents received. Please visit the Flising office with your vehicle, registration papers and licence for confirmation.'
            : 'Upload your Profile Photo, Licence, Car Photo, Plate Number, and Car Model below.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 44),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
    required bool editable,
  }) {
    final hasImage = localFile != null || networkUrl != null;
    ImageProvider? imageProvider;
    if (localFile != null) imageProvider = FileImage(localFile);
    else if (networkUrl != null && networkUrl.isNotEmpty) imageProvider = NetworkImage(networkUrl);

    return Container(
      decoration: BoxDecoration(color: darkSurface, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
            image: imageProvider != null ? DecorationImage(image: imageProvider, fit: BoxFit.cover) : null,
          ),
          child: imageProvider != null ? null : Icon(icon, color: Colors.white54),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
        subtitle: Text(
          editable ? (hasImage ? 'Ready to submit' : subtitle) : (_isVerified ? 'Verified ✓' : 'Submitted'),
          style: TextStyle(fontSize: 12, color: hasImage ? successGreen : Colors.white38),
        ),
        trailing: editable
            ? ElevatedButton(
                onPressed: () => _pickImage(slot),
                style: ElevatedButton.styleFrom(
                  backgroundColor: flisingOrange,
                  minimumSize: const Size(76, 34),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(hasImage ? 'CHANGE' : 'UPLOAD', style: const TextStyle(color: Colors.white, fontSize: 12)),
              )
            : Icon(_isVerified ? Icons.check_circle : Icons.hourglass_top, color: _isVerified ? successGreen : Colors.orange),
      ),
    );
  }
}
