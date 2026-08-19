import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/theme.dart';
import 'render/grain.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(systemOverlay);
  await SystemChrome.setPreferredOrientations(
      DeviceOrientation.values);
  await GrainTexture.ensureLoaded();
  runApp(const ProviderScope(child: CartaApp()));
}
