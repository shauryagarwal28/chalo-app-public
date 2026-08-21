import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';

class OtherRiderProfileScreen extends StatelessWidget {
  final String name;
  final String bike;
  final bool isNewRider;
  final List<Map<String, String>> selectedRideTypes;

  const OtherRiderProfileScreen({
    super.key,
    required this.name,
    required this.bike,
    this.isNewRider = false,
    this.selectedRideTypes = const [],
  });

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
                // Top bar — back button only, no edit control (read-only view)
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
                          'Rider Profile',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
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
                        Text(
                          name,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                        ),
                        if (isNewRider) ...[
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
                        ],
                        const SizedBox(height: 28),
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
                        const SizedBox(height: 20),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'BIKE',
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
                                    bike,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ChaloColors.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (selectedRideTypes.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'RIDES INTO',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ChaloColors.textSecondary, letterSpacing: 1.2),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: selectedRideTypes.map((type) {
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
                        ],
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
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
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
