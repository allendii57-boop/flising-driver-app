import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'main_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _isResending = false;

  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showSnack('Please enter your email and password.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user!;

      // Reload to get latest emailVerified status from Firebase
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser!;

      // ✅ SECURITY GATE — block unverified drivers
      if (!refreshed.emailVerified) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        _showVerificationDialog();
        return;
      }

      // ✅ FIRST VERIFIED LOGIN — write driver profile to DB now
      final dbRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
      ).ref('drivers/${refreshed.uid}/profile');

      try {
        final snap = await dbRef.get().timeout(const Duration(seconds: 5));
        if (!snap.exists) {
          // Reject passengers trying to log into driver app
          final passSnap = await FirebaseDatabase.instanceFor(
            app: Firebase.app(),
            databaseURL: "https://flising-default-rtdb.asia-southeast1.firebasedatabase.app",
          ).ref("users/passengers/${refreshed.uid}").get().timeout(const Duration(seconds: 5));
          if (passSnap.exists) {
            await FirebaseAuth.instance.signOut();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("This account is registered as a passenger. Please use the Flising Passenger app."), backgroundColor: Colors.redAccent),
            );
            return;
          }
          // First time verified — write profile
          await dbRef.set({
            'fullName': refreshed.displayName ?? '',
            'email': refreshed.email ?? '',
            'isVerified': false,       // admin verification (license check)
            'pendingApproval': false,
            'vehicleType': 'car',
            'isOnline': false,
            'registeredAt': ServerValue.timestamp,
          }).timeout(const Duration(seconds: 5));
        }
      } catch (e) {
        // DB write failed — still allow login, profile will retry next time
        debugPrint('DB write skipped: $e');
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverMainScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No driver account found for that email.';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Incorrect password. Please try again.';
          break;
        case 'user-disabled':
          msg = 'This account has been disabled. Contact support.';
          break;
        case 'too-many-requests':
          msg = 'Too many attempts. Please wait and try again.';
          break;
        default:
          msg = e.message ?? 'Login failed.';
      }
      _showSnack(msg, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showVerificationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: flisingOrange.withOpacity(0.4)),
        ),
        title: const Text(
          'Email Not Verified',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'You must verify your email before logging in.\n\nCheck your inbox for the verification link.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: _isResending ? null : () async {
              Navigator.pop(ctx);
              await _resendVerificationEmail();
            },
            child: _isResending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Resend Email',
                    style: TextStyle(
                      color: flisingOrange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _resendVerificationEmail() async {
    setState(() => _isResending = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        _showSnack('Enter your email and password first.', isError: true);
        return;
      }

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.sendEmailVerification();
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        _showSnack('Verification email resent. Check your inbox.', isError: false);
      }
    } catch (e) {
      if (mounted) _showSnack('Could not resend email. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isResending = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/images/flising_new_logo.jpg',
                  height: 80,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.local_taxi, size: 80, color: flisingOrange),
                ),
                const SizedBox(height: 20),
                Text(
                  'DRIVER PORTAL',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: flisingOrange,
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Connect to the Flising partner network.',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 50),

                // EMAIL
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.email_outlined, color: flisingOrange),
                    filled: true,
                    fillColor: darkSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: flisingOrange, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // PASSWORD
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.lock_outline, color: flisingOrange),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(
                          () => _isPasswordVisible = !_isPasswordVisible),
                    ),
                    filled: true,
                    fillColor: darkSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: flisingOrange, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // LOGIN BUTTON
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: flisingOrange,
                    disabledBackgroundColor: flisingOrange.withOpacity(0.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 3))
                      : const Text(
                          'LOGIN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
                const SizedBox(height: 25),

                // REGISTER LINK
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterScreen()),
                  ),
                  child: const Text(
                    'New partner? Apply to drive here.',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
