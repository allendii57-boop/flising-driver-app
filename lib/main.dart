import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notification_service.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'splash_screen.dart';

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

  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler
  );

  await NotificationService.initialize();

  // 3. Launch the App
  runApp(const FlisingDriverApp());
}

class FlisingDriverApp extends StatelessWidget {
  const FlisingDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flising Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFFE9692C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE9692C),
          secondary: Color(0xFFE9692C),
          surface: Color(0xFF1C1C1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFFE9692C)),
          centerTitle: true,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
