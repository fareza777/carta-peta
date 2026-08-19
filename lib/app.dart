import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'ui/splash_screen.dart';

class CartaApp extends StatelessWidget {
  const CartaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CARTA',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashScreen(),
      builder: (context, child) => MediaQuery.withNoTextScaling(child: child!),
    );
  }
}
