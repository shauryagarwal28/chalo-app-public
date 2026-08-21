import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/mock_user_state.dart';
import '../widgets/metallic_card.dart';
import 'kyc_approved_screen.dart';

class KycPendingScreen extends StatelessWidget {
  const KycPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.hourglass_top_rounded, size: 56, color: ChaloColors.primary),
              const SizedBox(height: 20),
              const Text('Verification in Progress', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ChaloColors.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'We review documents within 24 hours',
                style: TextStyle(fontSize: 14, color: ChaloColors.textSecondary.withOpacity(0.9)),
              ),
              const SizedBox(height: 32),
              MetallicCard(
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: const [
                      _TimelineStep(icon: Icons.check_circle, label: 'Documents uploaded', done: true),
                      _TimelineDivider(),
                      _TimelineStep(icon: Icons.autorenew, label: 'Review in progress', done: true, active: true),
                      _TimelineDivider(),
                      _TimelineStep(icon: Icons.verified, label: 'Verified badge unlocked', done: false),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              MetallicCard(
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'You can continue using Active Ride Mode while we review your documents.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: ChaloColors.textSecondary),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    MockUserState.isVerified = true;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const KycApprovedScreen()),
                    );
                  },
                  child: const Text('Simulate: Approved (demo only)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;
  final bool active;

  const _TimelineStep({required this.icon, required this.label, required this.done, this.active = false});

  @override
  Widget build(BuildContext context) {
    final color = done ? (active ? ChaloColors.primary : Colors.greenAccent) : ChaloColors.textDisabled;
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: done ? ChaloColors.textPrimary : ChaloColors.textDisabled)),
        ),
      ],
    );
  }
}

class _TimelineDivider extends StatelessWidget {
  const _TimelineDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [Container(width: 22, alignment: Alignment.center, child: Container(width: 1, height: 16, color: ChaloColors.borderShine))]),
    );
  }
}
