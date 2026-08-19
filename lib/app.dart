import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'ui/home/home_screen.dart';

class CartaApp extends StatelessWidget {
  const CartaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CARTA',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
      builder: (context, child) => MediaQuery.withNoTextScaling(child: child!),
    );
  }
}
