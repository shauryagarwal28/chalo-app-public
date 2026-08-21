import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'discover_rides_screen.dart';

class KycApprovedScreen extends StatelessWidget {
  const KycApprovedScreen({super.key});

  static const _unlocked = [
    'Discover public rides',
    'Post your own ride',
    'Build your rating',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ChaloColors.primary.withOpacity(0.12),
                  border: Border.all(color: ChaloColors.primary, width: 2),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.verified, color: ChaloColors.primary, size: 48),
              ),
              const SizedBox(height: 20),
              const Text("You're Verified", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: ChaloColors.textPrimary)),
              const SizedBox(height: 8),
              Text('Community Mode is now unlocked', style: TextStyle(fontSize: 14, color: ChaloColors.textSecondary.withOpacity(0.9))),
              const SizedBox(height: 28),
              MetallicCard(
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: _unlocked
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 18),
                                const SizedBox(width: 12),
                                Expanded(child: Text(item, style: const TextStyle(color: ChaloColors.textPrimary, fontSize: 14))),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const DiscoverRidesScreen()),
                  ),
                  child: const Text('Browse Rides'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
