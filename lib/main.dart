import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ads/ad_banner.dart';
import 'app.dart';
import 'core/theme.dart';
import 'render/grain.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(systemOverlay);
  await SystemChrome.setPreferredOrientations(
      DeviceOrientation.values);
  await GrainTexture.ensureLoaded();

  // Ads initialise in the background: a slow network must never hold up the
  // splash screen, and the app works perfectly with no ads at all.
  final container = ProviderContainer();
  unawaited(container.read(adServiceProvider).initialize());
  runApp(UncontrolledProviderScope(
    container: container,
    child: const CartaApp(),
  ));
}
