import 'package:flutter/material.dart';
import 'FaceVerificationScreen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Offline Face Verification',
      theme: ThemeData(
        primaryColor: const Color(0xFF3F51B5), // Blue for app bar/buttons
        scaffoldBackgroundColor: Colors.white, // White background
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F51B5), // Blue buttons
            foregroundColor: Colors.white, // White text
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3F51B5), // Blue app bar
          foregroundColor: Colors.white, // White text/icons
        ),
      ),
      home: const FaceVerificationScreen(),
    );
  }
}