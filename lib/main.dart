import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';

void main() => runApp(const Img2PdfApp());

class Img2PdfApp extends StatelessWidget {
  const Img2PdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FotoPDF',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      home: const SplashScreen(next: HomeScreen()),
    );
  }
}
