import 'package:flutter/material.dart';
import 'dart:math';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(),
            Image.asset('assets/images/flising_new_logo.jpg',
                width: MediaQuery.of(context).size.width * 0.6),
            const SizedBox(height: 12),
            const Text('DRIVER',
                style: TextStyle(color: Color(0xFFE9692C), fontSize: 36,
                    fontWeight: FontWeight.w900, letterSpacing: 8)),
            const SizedBox(height: 48),
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => CustomPaint(
                size: const Size(180, 180),
                painter: _RingPainter(_controller.value),
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(bottom: 32),
              child: Text('FROM VANIMO TO THE WORLD',
                  style: TextStyle(color: Colors.white54, fontSize: 13,
                      letterSpacing: 2)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    final glowPaint = Paint()
      ..color = const Color(0xFFE9692C).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius, glowPaint);

    final orangePaint = Paint()
      ..color = const Color(0xFFE9692C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, orangePaint);

    final arcPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2 * pi * progress - pi / 2,
      pi * 1.2,
      false,
      arcPaint,
    );

    final dotAngle = 2 * pi * 0.85 - pi / 2;
    final dotPos = Offset(
      center.dx + radius * cos(dotAngle),
      center.dy + radius * sin(dotAngle),
    );
    canvas.drawCircle(dotPos, 8, Paint()..color = const Color(0xFFE9692C));
    canvas.drawCircle(dotPos, 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
