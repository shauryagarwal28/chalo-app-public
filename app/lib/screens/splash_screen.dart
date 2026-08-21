import 'package:flutter/material.dart';
import '../theme/colors.dart';
import 'phone_entry_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF232B31), // gunmetal top — lighter, like light hitting metal
              Color(0xFF1A1F23), // gunmetal base
              Color(0xFF141920), // darker bottom
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Bike icon + wordmark
                _BikeIcon(),
                const SizedBox(height: 32),
                _Wordmark(),
                const SizedBox(height: 12),
                _Tagline(),

                const Spacer(flex: 3),

                // Buttons
                _GetStartedButton(),
                const SizedBox(height: 12),
                _SignInButton(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BikeIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF2D3439), Color(0xFF1A1F23)],
        ),
        border: Border.all(color: ChaloColors.borderShine, width: 1),
        boxShadow: [
          BoxShadow(
            color: ChaloColors.primary.withOpacity(0.25),
            blurRadius: 32,
            spreadRadius: 4,
          ),
          BoxShadow(
            color: ChaloColors.borderShine.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: const Icon(
        Icons.two_wheeler,
        size: 56,
        color: ChaloColors.primary,
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
        children: [
          TextSpan(
            text: 'Ch',
            style: TextStyle(color: ChaloColors.textPrimary),
          ),
          TextSpan(
            text: 'a',
            style: TextStyle(
              color: ChaloColors.primary,
              shadows: [
                Shadow(
                  color: ChaloColors.primaryGlow,
                  blurRadius: 16,
                ),
              ],
            ),
          ),
          TextSpan(
            text: 'lo',
            style: TextStyle(color: ChaloColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Tagline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, ChaloColors.borderShine],
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'RIDE TOGETHER',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ChaloColors.textSecondary,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 32,
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [ChaloColors.borderShine, Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}

class _GetStartedButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: ChaloColors.primary.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
        ),
        child: const Text('Get Started'),
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: ChaloColors.borderShine, width: 1),
        backgroundColor: ChaloColors.bgCard.withOpacity(0.5),
      ),
      child: const Text(
        'Sign In',
        style: TextStyle(color: ChaloColors.textSecondary),
      ),
    );
  }
}
