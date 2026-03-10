import 'package:flutter/material.dart';
import 'game_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const GameScreen(),
            transitionDuration: const Duration(milliseconds: 500),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      }
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
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // LostKit Mobile
              const Text(
                'LostKit Mobile',
                style: TextStyle(
                  fontFamily: 'RuneScape',
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFCC0000),
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 6),
              // by
              const Text(
                'by',
                style: TextStyle(
                  fontFamily: 'RuneScape',
                  fontSize: 15,
                  color: Color(0xFF880000),
                  letterSpacing: 2,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              // Logo
              Image.asset(
                'assets/losthqlogo.png',
                width: 170,
                height: 85,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text(
                  'LostHQ',
                  style: TextStyle(
                    fontFamily: 'RuneScape',
                    fontSize: 30,
                    color: Color(0xFFCC0000),
                    letterSpacing: 4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // & Akg
              const Text(
                '& Akg',
                style: TextStyle(
                  fontFamily: 'RuneScape',
                  fontSize: 16,
                  color: Color(0xFF880000),
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 40),
              // Loading bar
              SizedBox(
                width: 190,
                child: LinearProgressIndicator(
                  backgroundColor: const Color(0xFF1A0000),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFFCC0000)),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Loading...',
                style: TextStyle(
                  fontFamily: 'RuneScape',
                  fontSize: 12,
                  color: Color(0xFF660000),
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
