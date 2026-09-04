import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'past_rides_screen.dart';
import 'profile_creation_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // Mock data — mirrors what profile_creation_screen.dart collects.
  // No persistence layer exists yet, so this is static rather than
  // sourced from the earlier onboarding step (see current-implementation.md).
  static const _name = 'Rahul Sharma';
  static const _bike = 'Royal Enfield Himalayan';
  static const _selectedRideTypeIds = {'highway', 'mountain', 'weekend'};

  static const List<Map<String, String>> _rideTypes = [
    {'id': 'highway', 'label': 'Highway Cruising', 'icon': '🛣️'},
    {'id': 'mountain', 'label': 'Mountain / Ghats', 'icon': '⛰️'},
    {'id': 'sunrise', 'label': 'Sunrise / Early Morning', 'icon': '🌅'},
    {'id': 'weekend', 'label': 'Weekend Day Rides', 'icon': '☀️'},
    {'id': 'touring', 'label': 'Multi-Day Touring', 'icon': '🗺️'},
    {'id': 'city', 'label': 'Café Racer / City Rides', 'icon': '☕'},
    {'id': 'offroad', 'label': 'Off-Road / Dirt Tracks', 'icon': '🏕️'},
  ];

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
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
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
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProfileCreationScreen(prefillName: _name)),
                        ),
                        child: MetallicCard(
                          borderRadius: BorderRadius.circular(12),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.edit_outlined, color: ChaloColors.textSecondary, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),

                        // Photo + name
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ChaloColors.bgCard,
                            border: Border.all(color: ChaloColors.borderShine, width: 1.5),
                            boxShadow: [
                              BoxShadow(color: ChaloColors.primary.withOpacity(0.15), blurRadius: 20, spreadRadius: 2),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.person_outline, size: 36, color: ChaloColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          _name,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                        ),
                        const SizedBox(height: 6),
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

                        // Stats strip — same shape as Home's, deliberately not showing
                        // a rating here since that system doesn't exist yet.
                        MetallicCard(
                          borderRadius: BorderRadius.circular(16),
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          child: const Row(
                            children: [
                              _StatItem(value: '0', label: 'Rides'),
                              _StatDivider(),
                              _StatItem(value: '0 km', label: 'Distance'),
                              _StatDivider(),
                              _StatItem(value: '0', label: 'No-shows'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Entry point to S19d, "Past Rides (Report Access)" —
                        // a new, separate link, deliberately not the ride-count
                        // stat above (that stat stays inert per
                        // `product/decisions/13-incident-reporting.md`'s
                        // "New Scope Surfaced: Reporting After Leaving a Ride").
                        // Own-profile only — not shown on `other_rider_profile_screen.dart`.
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PastRidesScreen()),
                            ),
                            icon: const Icon(Icons.flag_outlined, size: 16),
                            label: const Text('Report an Incident from a Past Ride'),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Bike details
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'YOUR BIKE',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ChaloColors.textSecondary, letterSpacing: 1.2),
                          ),
                        ),
                        const SizedBox(height: 10),
                        MetallicCard(
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                const Icon(Icons.two_wheeler, color: ChaloColors.primary, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _bike,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ChaloColors.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Rides you're into
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'RIDES YOU\'RE INTO',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ChaloColors.textSecondary, letterSpacing: 1.2),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _rideTypes.where((t) => _selectedRideTypeIds.contains(t['id'])).map((type) {
                            return MetallicCard(
                              borderRadius: BorderRadius.circular(12),
                              hasOrangeAccent: true,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(type['icon']!, style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      type['label']!,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.primary),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
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

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: ChaloColors.textSecondary)),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: ChaloColors.borderShine.withOpacity(0.3));
  }
}
