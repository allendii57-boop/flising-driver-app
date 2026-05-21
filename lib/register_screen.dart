import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

// Your exact file name
import 'main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // 1. Text Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isPasswordVisible = false;
  bool _isLoading = false; // THE MAGIC SPINNER SWITCH!

  // Premium Theme Colors
  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 2. The Firebase Registration Brain
  void _handleRegister() async {
    final String name = _nameController.text.trim();
    final String phone = _phoneController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    // Safety check: Make sure they didn't leave anything blank!
    if (name.isEmpty || phone.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields!', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFFD32F2F),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() { _isLoading = true; });

    try {
      // A. Create the key in Firebase Authentication
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // B. Save their profile info to your exact Asia server!
      DatabaseReference driverRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app'
      ).ref().child('drivers/${userCredential.user!.uid}/profile');

      await driverRef.set({
        "fullName": name,
        "phoneNumber": phone,
        "email": email,
        "registeredAt": ServerValue.timestamp,
      });

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration Successful! Welcome to Flising.', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // C. Smash through to the Dashboard!
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DriverMainScreen()),
      );

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String errorMessage = "Registration Failed: ${e.message}";
      if (e.code == 'weak-password') errorMessage = 'The password provided is too weak.';
      if (e.code == 'email-already-in-use') errorMessage = 'An account already exists for that email.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFD32F2F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('General Error: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFD32F2F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  // A tiny helper tool to keep the code clean and premium!
  Widget _buildTextField(TextEditingController controller, String label, IconData icon, TextInputType type) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          prefixIcon: Icon(icon, color: flisingOrange),
          filled: true,
          fillColor: darkSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: flisingOrange, width: 2)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Premium Dark theme
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- BACK BUTTON ---
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(height: 10),

              // --- HEADER ---
              Text(
                'Create Account',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: flisingOrange, letterSpacing: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Join Flising and start earning.',
                style: TextStyle(fontSize: 16, color: Colors.white54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // --- FULL NAME ---
              _buildTextField(_nameController, 'Full Name', Icons.person_outline, TextInputType.name),

              // --- PHONE NUMBER ---
              _buildTextField(_phoneController, 'Phone Number', Icons.phone_android, TextInputType.phone),

              // --- EMAIL ---
              _buildTextField(_emailController, 'Email Address', Icons.email_outlined, TextInputType.emailAddress),

              // --- PASSWORD ---
              TextFormField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: Icon(Icons.lock_outline, color: flisingOrange),
                  suffixIcon: IconButton(
                    icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.white54),
                    onPressed: () {
                      setState(() { _isPasswordVisible = !_isPasswordVisible; });
                    },
                  ),
                  filled: true,
                  fillColor: darkSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: flisingOrange, width: 2)),
                ),
              ),
              const SizedBox(height: 40),

              // --- REGISTER BUTTON ---
              ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: flisingOrange,
                  disabledBackgroundColor: flisingOrange.withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 5,
                ),
                child: _isLoading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : const Text(
                        'REGISTER',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
 