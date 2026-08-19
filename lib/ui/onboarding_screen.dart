import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../model/map_data.dart';
import '../model/poster_config.dart';
import '../presets/demo_map.dart';
import '../presets/format_presets.dart';
import '../presets/style_presets.dart';
import '../render/path_cache.dart';
import '../render/poster_renderer.dart';
import '../state/providers.dart';
import 'home/home_screen.dart';
import 'widgets/common.dart';
import 'widgets/poster_view.dart';

/// First-run tour. Every page shows a real poster drawn by the real renderer
/// from a procedural city, so nothing here is a screenshot and nothing needs
/// the network before the user has even searched for anything.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  late final MapDataSet _demo = buildDemoMap();
  late final MapPathCache _cache = MapPathCache(_demo);
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      final p = _pages.hasClients ? (_pages.page ?? 0) : 0.0;
      if ((p - _page).abs() > 0.001) setState(() => _page = p);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _cache.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(prefsStoreProvider).setOnboarded();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  List<_Page> _content(S s) => [
        _Page(
          title: s.onboard1Title,
          body: s.onboard1Body,
          styleId: 'minimal',
          poster: const PosterConfig(
            enabled: false,
            shape: ShapeMask.rectangle,
            margin: 0.055,
          ),
        ),
        _Page(
          title: s.onboard2Title,
          body: s.onboard2Body,
          styleId: 'neon',
          poster: const PosterConfig(
            enabled: false,
            shape: ShapeMask.fill,
            margin: 0,
          ),
        ),
        _Page(
          title: s.onboard3Title,
          body: s.onboard3Body,
          styleId: 'topo',
          poster: const PosterConfig(
            enabled: false,
            shape: ShapeMask.arch,
            margin: 0.06,
          ),
          labels: true,
        ),
        _Page(
          title: s.onboard4Title,
          body: s.onboard4Body,
          styleId: 'luxury',
          poster: const PosterConfig(
            title: 'CARTA',
            subtitle: 'MAP ART STUDIO',
            showCoordinates: false,
            frame: FrameStyle.hairline,
            margin: 0.07,
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final pages = _content(s);
    final index = _page.round().clamp(0, pages.length - 1);
    final last = index == pages.length - 1;

    return Scaffold(
      backgroundColor: Shade.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(
                  s.skip,
                  style: const TextStyle(color: Shade.textDim, fontSize: 14),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: pages.length,
                itemBuilder: (context, i) {
                  // Distance from the settled position drives a small parallax
                  // so the artwork feels like it sits behind the copy.
                  final delta = (_page - i).clamp(-1.0, 1.0);
                  return _PageView(
                    page: pages[i],
                    cache: _cache,
                    delta: delta,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 22),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == index ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == index ? Shade.accent : Shade.line,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: last ? s.startCreating : s.next,
                    icon: last ? Icons.auto_awesome : Icons.arrow_forward,
                    onPressed: () {
                      if (last) {
                        _finish();
                      } else {
                        _pages.nextPage(
                          duration: const Duration(milliseconds: 340),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page {
  const _Page({
    required this.title,
    required this.body,
    required this.styleId,
    required this.poster,
    this.labels = false,
  });

  final String title;
  final String body;
  final String styleId;
  final PosterConfig poster;
  final bool labels;
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page, required this.cache, required this.delta});

  final _Page page;
  final MapPathCache cache;
  final double delta;

  @override
  Widget build(BuildContext context) {
    final base = kStylePresets.firstWhere((s) => s.id == page.styleId);
    final style = page.labels
        ? base.copyWith(showLabels: true, labelScale: 0.85, reliefStrength: 0)
        : base;

    final scene = PosterScene(
      paths: cache,
      style: style,
      poster: page.poster,
      format: kFormats.first,
      showAttribution: false,
      // A slow drift across the demo city as pages change.
      pan: Offset(delta * 0.06, 0),
      zoom: 1.0 + (1 - delta.abs()) * 0.05,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 8),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Transform.translate(
                offset: Offset(-delta * 26, 0),
                child: Transform.rotate(
                  angle: delta * -0.02,
                  child: PosterFrame(scene: scene),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          Opacity(
            opacity: math.max(0, 1 - delta.abs() * 1.6),
            child: Column(
              children: [
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Shade.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Shade.textDim,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
