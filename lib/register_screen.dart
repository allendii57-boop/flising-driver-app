import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  final Color flisingOrange = const Color(0xFFE9692C);

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || phone.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnack('Please fill in all fields.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    UserCredential? userCredential;

    try {
      // 1. Create Auth account
      userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 2. Save profile to database BEFORE sending verification
      await FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
      ).ref('drivers/${userCredential.user!.uid}/profile').set({
        'fullName': name,
        'phoneNumber': phone,
        'email': email,
        'isVerified': false,
        'pendingApproval': false,
        'isOnline': false,
        'registeredAt': ServerValue.timestamp,
      });

      // 3. Send verification email
      await userCredential.user?.sendEmailVerification();

      // 4. Sign out — broken sessions never enter the app
      await _auth.signOut();

      if (!mounted) return;
      _showSnack(
        'Account created! Check your email to verify before logging in.',
        isError: false,
      );

      await Future.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    } on FirebaseAuthException catch (e) {
      // If DB write failed after auth was created, delete the auth account
      if (userCredential != null) {
        await userCredential.user?.delete();
      }
      if (mounted) _showSnack(e.message ?? 'Registration failed.', isError: true);
    } catch (e) {
      if (userCredential != null) {
        await userCredential.user?.delete();
      }
      if (mounted) _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? const Color(0xFFD32F2F) : const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: Icon(icon, color: flisingOrange),
          enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white30)),
          focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: flisingOrange)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          children: [
            Image.asset(
              'assets/images/flising_logo.png',
              height: 60,
              errorBuilder: (c, e, s) =>
                  Icon(Icons.local_taxi, color: flisingOrange, size: 60),
            ),
            const SizedBox(height: 20),
            const Text('Create Driver Account',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Join the Flising Driver Network.',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 40),

            _buildField(_nameController, 'Full Name', Icons.person_outline,
                type: TextInputType.name),
            _buildField(_phoneController, 'Phone Number', Icons.phone_android,
                type: TextInputType.phone),
            _buildField(_emailController, 'Email Address', Icons.email_outlined,
                type: TextInputType.emailAddress),

            // Password field with toggle
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Password (Min. 6 characters)',
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: Icon(Icons.lock_outline, color: flisingOrange),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.white54),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: flisingOrange)),
              ),
            ),
            const SizedBox(height: 50),

            ElevatedButton(
              onPressed: _isLoading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: flisingOrange,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('SIGN UP',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
