import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../render/grain.dart';
import '../state/providers.dart';
import 'home/home_screen.dart';
import 'onboarding_screen.dart';

/// Launch screen: the CARTA mark draws itself while the app warms up.
///
/// The streets are stroked in with `PathMetric.extractPath`, the same idea a
/// plotter uses, so the mark is genuinely being drawn rather than faded in.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );

  late final Animation<double> _draw = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.05, 0.72, curve: Curves.easeInOutCubic),
  );

  late final Animation<double> _word = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.42, 0.92, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _settle = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _boot();
  }

  Future<void> _boot() async {
    final prefs = ref.read(prefsStoreProvider);
    final results = await Future.wait([
      GrainTexture.ensureLoaded().then((_) => false),
      prefs.hasOnboarded(),
      _controller.forward().orCancel.then((_) => false).catchError((_) => false),
    ]);
    if (!mounted) return;
    final onboarded = results[1];
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 520),
        pageBuilder: (_, __, ___) =>
            onboarded ? const HomeScreen() : const OnboardingScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      backgroundColor: Shade.bg,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final size = math.min(MediaQuery.of(context).size.width * 0.52, 240.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.94 + 0.06 * _settle.value,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: CustomPaint(painter: _MarkPainter(_draw.value)),
                  ),
                ),
                SizedBox(height: size * 0.22),
                Opacity(
                  opacity: _word.value,
                  child: Text(
                    'CARTA',
                    style: TextStyle(
                      color: Shade.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      // Tracking opens up as the wordmark lands.
                      letterSpacing: 2 + 12 * _word.value,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: _word.value * 0.8,
                  child: Text(
                    s.tagline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Shade.textFaint,
                      fontSize: 12.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - size.width * 0.04;

    // Plate
    canvas.drawCircle(centre, radius, Paint()..color = const Color(0xFF141210));

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: centre, radius: radius)));

    final streets = _streets(centre, radius);
    final soft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.012
      ..color = Shade.accent.withValues(alpha: 0.34);
    final bright = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.022
      ..color = Shade.accent;

    for (var i = 0; i < streets.length; i++) {
      // Stagger each street so the mark builds up instead of appearing at once.
      final start = i / streets.length * 0.45;
      final t = ((progress - start) / (1 - start)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      _drawPartial(canvas, streets[i].$1, t, streets[i].$2 ? bright : soft);
    }
    canvas.restore();

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.014
        ..color = Shade.accent.withValues(alpha: 0.35 + 0.65 * progress),
    );
  }

  static void _drawPartial(Canvas canvas, Path path, double t, Paint paint) {
    if (t >= 0.999) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
    }
  }

  /// A small, deliberately readable street pattern: two ring roads, radial
  /// avenues and a river.
  static List<(Path, bool)> _streets(Offset c, double r) {
    final out = <(Path, bool)>[];

    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + 0.3;
      out.add((
        Path()
          ..moveTo(c.dx + math.cos(a) * r * 0.08, c.dy + math.sin(a) * r * 0.08)
          ..lineTo(c.dx + math.cos(a) * r * 1.2, c.dy + math.sin(a) * r * 1.2),
        i.isEven,
      ));
    }

    for (final factor in [0.42, 0.74]) {
      out.add((
        Path()..addOval(Rect.fromCircle(center: c, radius: r * factor)),
        factor > 0.5,
      ));
    }

    final river = Path();
    for (var i = 0; i <= 24; i++) {
      final x = c.dx - r * 1.2 + (r * 2.4) * i / 24;
      final y = c.dy + r * 0.52 + math.sin(i / 24 * math.pi * 2) * r * 0.16;
      if (i == 0) {
        river.moveTo(x, y);
      } else {
        river.lineTo(x, y);
      }
    }
    out.add((river, false));
    return out;
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.progress != progress;
}
