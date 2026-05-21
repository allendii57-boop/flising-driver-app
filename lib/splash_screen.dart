import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

// Make sure these match your actual files!
import 'login_screen.dart'; 
import 'main_screen.dart'; 

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    _controller.forward();

    Timer(const Duration(milliseconds: 3500), () {
      User? user = FirebaseAuth.instance.currentUser;
      
      if (user != null) {
        // FIXED: Now correctly routes to the DriverMainScreen class!
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DriverMainScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Image.asset(
                'assets/images/flising_logo.png', 
                width: 200,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.local_taxi, 
                  color: Color(0xFFE9692C), 
                  size: 100
                ),
              ),
              const SizedBox(height: 25),
              const Text(
                "FLISING DRIVER",
                style: TextStyle(
                  color: Color(0xFFE9692C), 
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4.0,
                ),
              ),
              const Spacer(),
              const CircularProgressIndicator(
                color: Color(0xFFE9692C),
                strokeWidth: 3,
              ),
              const SizedBox(height: 30),
              const Text(
                "FROM VANIMO TO THE WORLD",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 3.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}