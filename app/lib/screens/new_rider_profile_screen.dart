import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'discover_rides_screen.dart';

class NewRiderProfileScreen extends StatelessWidget {
  final String name;

  const NewRiderProfileScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1.5, -1.5),
                    end: Alignment(1.5, 1.5),
                    colors: [Color(0xFF2A3540), Color(0xFF1A1F23), Color(0xFF1E2428), Color(0xFF1A1F23)],
                    stops: [0.0, 0.35, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: MetallicCard(
                          borderRadius: BorderRadius.circular(12),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.arrow_back_ios_new, color: ChaloColors.textSecondary, size: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Profile',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ChaloColors.bgCard,
                      border: Border.all(color: ChaloColors.borderShine, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.person_outline, size: 40, color: ChaloColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: ChaloColors.primary),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'New Rider',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ChaloColors.primary),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    "You haven't ridden with Chalo yet",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: ChaloColors.textSecondary.withOpacity(0.9)),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DiscoverRidesScreen()),
                      ),
                      child: const Text('Find Your First Ride'),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
