import 'dart:math';

import 'package:flutter/material.dart';

class Starfield extends StatefulWidget {
  const Starfield({super.key, this.child});

  final Widget? child;

  @override
  State<Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<Starfield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    final rng = Random(42);
    _stars = List.generate(80, (_) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        r: rng.nextDouble() * 1.6 + 0.3,
        twinkle: rng.nextDouble(),
      );
    });
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _StarPainter(_stars, _controller.value),
          child: widget.child,
        );
      },
    );
  }
}

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.r,
    required this.twinkle,
  });
  final double x;
  final double y;
  final double r;
  final double twinkle;
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.stars, this.t);
  final List<_Star> stars;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final star in stars) {
      final pulse = 0.4 + 0.6 * (0.5 + 0.5 * sin((t + star.twinkle) * pi * 2));
      paint.color = Colors.white.withValues(alpha: pulse * 0.7);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => oldDelegate.t != t;
}
