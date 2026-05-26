import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'package:firebase_core/firebase_core.dart';

// Flising Core Files
import 'firebase_options.dart';
import 'splash_screen.dart'; // <-- The Boot Sequence!

void main() async {
  // 1. Ensure Flutter engine is fully booted before talking to Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Safely connect to the Flising Cloud Backend
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("SUCCESS: Flising Firebase Engine Started.");
  } catch (error) {
    print("WARNING: Firebase failed to start! Error: $error");
  }
  
  // 3. Launch the App
  runApp(const FlisingDriverApp());
}

class FlisingDriverApp extends StatelessWidget {
  const FlisingDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flising Driver',
      debugShowCheckedModeBanner: false, // Removes the red debug banner for a production look
      
      // --- THE GLOBAL FLISING PREMIUM THEME ---
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFFE9692C), // Official Flising Orange
        
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE9692C),
          secondary: Color(0xFFE9692C),
          surface: Color(0xFF1C1C1E), // Premium Dark Surface for cards and dialogs
        ),
        
        // Forces all AppBars across the app to default to your premium look
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFFE9692C)),
          centerTitle: true,
        ),
      ), // <--- This closing parenthesis and comma was missing!
      
      home: const SplashScreen(), // Starts the cinematic boot sequence
    );
  }
}