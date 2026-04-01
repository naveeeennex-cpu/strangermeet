import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: Logo + Skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'S.',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'StrangerMeet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => context.go('/login'),
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Hero illustration area with floating elements
            Expanded(
              flex: 5,
              child: AnimatedBuilder(
                animation: _floatAnim,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // Geometric decorations
                      ..._buildDecorations(size),

                      // Center large profile circle
                      Positioned(
                        top: size.height * 0.03,
                        child: Transform.translate(
                          offset: Offset(0, _floatAnim.value),
                          child: _profileCircle(
                            100,
                            AppTheme.primaryColor,
                            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop&crop=face',
                            badge: 'follow',
                          ),
                        ),
                      ),

                      // Top-right smaller profile
                      Positioned(
                        top: size.height * 0.08,
                        right: size.width * 0.08,
                        child: Transform.translate(
                          offset: Offset(0, -_floatAnim.value * 0.7),
                          child: _profileCircle(
                            64,
                            const Color(0xFFFF6B9D),
                            'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop&crop=face',
                            badge: 'follow',
                          ),
                        ),
                      ),

                      // Bottom-left profile
                      Positioned(
                        bottom: size.height * 0.05,
                        left: size.width * 0.12,
                        child: Transform.translate(
                          offset: Offset(
                            _floatAnim.value * 0.5,
                            _floatAnim.value * 0.3,
                          ),
                          child: _profileCircle(
                            56,
                            Colors.blue.shade300,
                            'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=200&h=200&fit=crop&crop=face',
                          ),
                        ),
                      ),

                      // Large lime arrow
                      Positioned(
                        right: size.width * 0.12,
                        bottom: size.height * 0.03,
                        child: Transform.translate(
                          offset: Offset(0, _floatAnim.value * 0.4),
                          child: Transform.rotate(
                            angle: -0.3,
                            child: CustomPaint(
                              size: const Size(55, 66),
                              painter: _ArrowPainter(AppTheme.primaryColor),
                            ),
                          ),
                        ),
                      ),

                      // Pink arrow
                      Positioned(
                        left: size.width * 0.06,
                        top: size.height * 0.06,
                        child: Transform.translate(
                          offset: Offset(_floatAnim.value * 0.3, 0),
                          child: Transform.rotate(
                            angle: 0.8,
                            child: CustomPaint(
                              size: const Size(40, 48),
                              painter: _ArrowPainter(const Color(0xFFFF6B9D)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Bottom text + buttons
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'Best Social App to\nMake New Friends',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        height: 1.25,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'With StrangerMeet you will find new friends\nfrom various countries and regions of the world',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                        height: 1.5,
                      ),
                    ),
                    const Spacer(),
                    // Get Started
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => context.go('/signup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Get Started'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Login
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCircle(double size, Color color, String imageUrl, {String? badge}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.network(
              imageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: color.withOpacity(0.25),
                child: Icon(Icons.person, size: size * 0.45, color: Colors.black54),
              ),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            bottom: -4,
            left: (size - 52) / 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildDecorations(Size size) {
    final rng = Random(42);
    return [
      // Lime triangle
      Positioned(
        left: size.width * 0.18,
        top: 0,
        child: Transform.rotate(
          angle: 0.4,
          child: CustomPaint(
            size: const Size(45, 45),
            painter: _TrianglePainter(AppTheme.primaryColor.withOpacity(0.35)),
          ),
        ),
      ),
      // Pink dot
      Positioned(
        right: size.width * 0.22,
        top: 0,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF6B9D).withOpacity(0.4),
          ),
        ),
      ),
      // Blue square
      Positioned(
        left: size.width * 0.08,
        bottom: size.height * 0.12,
        child: Transform.rotate(
          angle: 0.5,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
      // Zigzag
      Positioned(
        right: size.width * 0.04,
        top: size.height * 0.16,
        child: CustomPaint(
          size: const Size(28, 20),
          painter: _ZigzagPainter(AppTheme.primaryColor),
        ),
      ),
      // Music notes
      Positioned(
        right: size.width * 0.28,
        bottom: size.height * 0.14,
        child: Icon(Icons.music_note, size: 16, color: Colors.grey[300]),
      ),
      Positioned(
        left: size.width * 0.2,
        top: size.height * 0.14,
        child: Icon(Icons.music_note, size: 13, color: Colors.grey[300]),
      ),
      // Sparkle
      Positioned(
        left: size.width * 0.32,
        bottom: size.height * 0.01,
        child: const Icon(Icons.auto_awesome, size: 15, color: Color(0xFFFF6B9D)),
      ),
      // Random small dots
      ...List.generate(6, (i) {
        final colors = [AppTheme.primaryColor, const Color(0xFFFF6B9D), Colors.blue.shade300, Colors.black26];
        return Positioned(
          left: rng.nextDouble() * size.width * 0.7 + size.width * 0.15,
          top: rng.nextDouble() * size.height * 0.25,
          child: Container(
            width: rng.nextDouble() * 4 + 3,
            height: rng.nextDouble() * 4 + 3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors[i % colors.length].withOpacity(0.4),
            ),
          ),
        );
      }),
    ];
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  _ArrowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width, size.height * 0.3)
      ..lineTo(size.width * 0.65, size.height * 0.3)
      ..lineTo(size.width * 0.65, size.height)
      ..lineTo(size.width * 0.35, size.height)
      ..lineTo(size.width * 0.35, size.height * 0.3)
      ..lineTo(0, size.height * 0.3)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ZigzagPainter extends CustomPainter {
  final Color color;
  _ZigzagPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * 0.5)
      ..lineTo(size.width * 0.25, 0)
      ..lineTo(size.width * 0.5, size.height * 0.5)
      ..lineTo(size.width * 0.75, 0)
      ..lineTo(size.width, size.height * 0.5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
