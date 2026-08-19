import 'package:flutter/material.dart';

import '../../render/poster_renderer.dart';

class _PosterPainter extends CustomPainter {
  _PosterPainter(this.scene);

  final PosterScene scene;

  @override
  void paint(Canvas canvas, Size size) => PosterRenderer.paint(canvas, size, scene);

  @override
  bool shouldRepaint(_PosterPainter old) => !identical(old.scene, scene);
}

/// Live, resolution-independent poster preview.
class PosterView extends StatelessWidget {
  const PosterView({super.key, required this.scene, this.borderRadius = 6});

  final PosterScene scene;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: scene.format.aspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _PosterPainter(scene),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// Poster preview with the drop shadow used on the studio canvas.
class PosterFrame extends StatelessWidget {
  const PosterFrame({super.key, required this.scene});

  final PosterScene scene;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 38, offset: Offset(0, 18)),
          BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: PosterView(scene: scene, borderRadius: 8),
    );
  }
}
