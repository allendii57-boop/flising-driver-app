import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Your exact file names!
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

  // Premium Theme Colors
  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    setState(() { _isLoading = true; });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      // Success! Route to the Driver Map
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DriverMainScreen()),
      );

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      
      String errorMessage = "Login Failed: ${e.message}";
      if (e.code == 'user-not-found') errorMessage = 'No driver found for that email.';
      if (e.code == 'wrong-password') errorMessage = 'Wrong password provided.';
      
      // Premium floating error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFD32F2F), // Warning Red
          behavior: SnackBarBehavior.floating,
        )
      );
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
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
                
                // --- PREMIUM LOGO BLOCK ---
                Image.asset(
                  'assets/images/flising_logo.png', 
                  height: 80,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(Icons.local_taxi, size: 80, color: flisingOrange),
                ),
                const SizedBox(height: 20),
                Text(
                  'DRIVER PORTAL',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: flisingOrange, letterSpacing: 2),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Connect to the Flising partner network.',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 50),

                // --- EMAIL INPUT ---
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: flisingOrange, width: 2)),
                  ),
                ),
                const SizedBox(height: 20),

                // --- PASSWORD INPUT ---
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

                // --- LOGIN BUTTON ---
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
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
                          'LOGIN',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5),
                        ),
                ),
                const SizedBox(height: 25),

                // --- REGISTER LINK ---
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const RegisterScreen()),
                    );
                  },
                  child: const Text(
                    "New partner? Apply to drive here.",
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