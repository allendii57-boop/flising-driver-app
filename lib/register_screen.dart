import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    UserCredential? userCredential;

    try {
      // 1. Create Firebase Auth account
      userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 2. Store name + phone in Auth profile (carried to DB only after verification)
      await userCredential.user?.updateDisplayName(name);

      // Store phone temporarily in photoURL field as a workaround
      // (Firebase Auth doesn't have a phone field for email/password accounts)
      // We will write the real profile to DB only after email is verified (in login_screen.dart)

      // 3. Send verification email
      await userCredential.user?.sendEmailVerification();

      // 4. Sign out immediately — NO DB write yet
      //    Firebase Database will NOT store any driver data until email is verified
    await _auth.signOut();

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
    _showSnack(
      'Account created! Check your email to verify before logging in.',
      isError: false,
    );
    } on FirebaseAuthException catch (e) {
      // Clean up — delete the Auth account so nothing broken is left
      try {
        await userCredential?.user?.delete();
      } catch (_) {}

      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'This email is already registered. Please log in instead.';
          break;
        case 'invalid-email':
          msg = 'Invalid email address.';
          break;
        case 'weak-password':
          msg = 'Password is too weak. Use at least 6 characters.';
          break;
        default:
          msg = e.message ?? 'Registration failed.';
      }
      if (mounted) _showSnack(msg, isError: true);
    } catch (e) {
      try {
        await userCredential?.user?.delete();
      } catch (_) {}
      if (mounted) _showSnack('Unexpected error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor:
          isError ? const Color(0xFFD32F2F) : const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    String? helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          helperText: helperText,
          helperStyle: const TextStyle(color: Colors.orange, fontSize: 11),
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
            const Text(
              'Create Driver Account',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Join the Flising Driver Network.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 40),

            // Full Name — must match license
            _buildField(
              _nameController,
              'Full Name (as on Driver\'s License)',
              Icons.person_outline,
              helperText: 'Class 3 or Class 6 license name',
            ),

            // Phone
            _buildField(
              _phoneController,
              'Phone Number',
              Icons.phone_android,
              type: TextInputType.phone,
            ),

            // Email
            _buildField(
              _emailController,
              'Email Address',
              Icons.email_outlined,
              type: TextInputType.emailAddress,
            ),

            // Password with toggle
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: TextFormField(
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
                      color: Colors.white54,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: flisingOrange)),
                ),
              ),
            ),

            // Notice banner
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 30),
              decoration: BoxDecoration(
                color: flisingOrange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: flisingOrange.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: flisingOrange, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Your full name must match your Class 3 or Class 6 driver\'s license exactly. '
                      'This name will be shown to passengers when you accept a ride.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

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
                  : const Text(
                      'SIGN UP',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
