import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';

void main() => runApp(const Img2PdfApp());

class Img2PdfApp extends StatelessWidget {
  const Img2PdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3949AB);
    return MaterialApp(
      title: 'FotoPDF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const SplashScreen(next: HomeScreen()),
    );
  }
}
