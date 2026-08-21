import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/mock_user_state.dart';
import '../widgets/metallic_card.dart';
import 'create_party_screen.dart';
import 'discover_rides_screen.dart';
import 'join_party_screen.dart';
import 'kyc_upload_screen.dart';
import 'post_a_ride_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: Stack(
        children: [
          // Subtle diagonal background sheen
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1.5, -1.5),
                    end: Alignment(1.5, 1.5),
                    colors: [
                      Color(0xFF2A3540),
                      Color(0xFF1A1F23),
                      Color(0xFF1E2428),
                      Color(0xFF1A1F23),
                    ],
                    stops: [0.0, 0.35, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        _TopBar(),
                        const SizedBox(height: 28),
                        _StatsStrip(),
                        const SizedBox(height: 32),
                        const _SectionLabel('What do you want to do?'),
                        const SizedBox(height: 16),
                        _MyCrewCard(),
                        const SizedBox(height: 14),
                        _DiscoverRidesCard(),
                        const SizedBox(height: 14),
                        _PostARideTestEntry(),
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
      bottomNavigationBar: _BottomNav(),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greeting(),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontSize: 13, color: ChaloColors.textSecondary),
            ),
            const SizedBox(height: 2),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                children: [
                  TextSpan(text: 'Ch'),
                  TextSpan(
                    text: 'a',
                    style: TextStyle(
                      color: ChaloColors.primary,
                      shadows: [Shadow(color: ChaloColors.primaryGlow, blurRadius: 10)],
                    ),
                  ),
                  TextSpan(text: 'lo'),
                ],
              ),
            ),
          ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          child: MetallicCard(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              child: const Icon(Icons.person_outline, color: ChaloColors.textSecondary, size: 22),
            ),
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final name = MockUserState.riderName ?? 'Rider';
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning, $name';
    if (hour < 17) return 'Good afternoon, $name';
    return 'Good evening, $name';
  }
}

class _StatsStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MetallicCard(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Row(
        children: [
          const _StatItem(value: '0', label: 'Rides'),
          _StatDivider(),
          const _StatItem(value: '—', label: 'Rating', isNewRider: true),
          _StatDivider(),
          const _StatItem(value: '0 km', label: 'Distance'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final bool isNewRider;

  const _StatItem({required this.value, required this.label, this.isNewRider = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          if (isNewRider)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: ChaloColors.primary),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'New Rider',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ChaloColors.primary),
              ),
            )
          else
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
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: ChaloColors.borderShine.withOpacity(0.3));
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: ChaloColors.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _MyCrewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MetallicCard(
      hasOrangeAccent: true,
      borderRadius: BorderRadius.circular(20),
      shadows: [
        BoxShadow(color: ChaloColors.primary.withOpacity(0.25), blurRadius: 28, offset: const Offset(0, 6)),
        BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
      ],
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ChaloColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ChaloColors.primary.withOpacity(0.4)),
                  ),
                  child: const Text(
                    'PRIVATE RIDE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: ChaloColors.primary, letterSpacing: 1.2),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'My Crew',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ride with your friends.\nCreate a party or join one.',
                  style: TextStyle(fontSize: 13, color: ChaloColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // Create Party — primary orange
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePartyScreen())),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: ChaloColors.primary,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(color: ChaloColors.primary.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: const Text(
                            'Create Party',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Join with Code — metallic secondary
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinPartyScreen())),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: ChaloColors.bgElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: ChaloColors.borderShine),
                          ),
                          child: const Text(
                            'Join with Code',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.textPrimary),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [ChaloColors.primaryGlow, ChaloColors.primary],
            ).createShader(bounds),
            child: const Icon(Icons.two_wheeler, size: 64, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _DiscoverRidesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverRidesScreen())),
      child: MetallicCard(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ChaloColors.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ChaloColors.borderShine),
                    ),
                    child: const Text(
                      'COMMUNITY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: ChaloColors.metalHighlight,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Discover Rides',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Find verified riders going\nyour way. Join the community.',
                    style: TextStyle(fontSize: 13, color: ChaloColors.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: ChaloColors.bgElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ChaloColors.borderShine),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Browse Rides',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.textPrimary),
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward, size: 14, color: ChaloColors.textSecondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8A9FAA), Color(0xFF4E5D66)],
              ).createShader(bounds),
              child: const Icon(Icons.explore_outlined, size: 72, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// A separate, deliberately lower-key entry point for Post a Ride, distinct
/// from `_DiscoverRidesCard` above — added 2026-08-18 as a testing
/// convenience, not a product decision. Community Mode (S11-S20) is still
/// gated as UI-shells-only ahead of Active Ride Mode validation
/// (`process/roadmap.md`), so this is intentionally styled as a slim
/// outlined row, not another full hero card or a bottom-nav tab — same
/// "stays icon/button-scale" restraint every other test-only affordance in
/// this app follows. It reuses `DiscoverRidesScreen._onPostARide`'s exact
/// KYC-gate logic (`MockUserState.isVerified`) rather than duplicating or
/// bypassing it — this shortcut skips the trip through Discover, not the
/// real KYC gate.
class _PostARideTestEntry extends StatelessWidget {
  void _onTap(BuildContext context) {
    if (MockUserState.isVerified) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PostARideScreen()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const KycUploadScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ChaloColors.borderDim),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_road, size: 18, color: ChaloColors.textSecondary),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Post a Ride (test shortcut)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.textPrimary),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Skips Discover — for testing only',
                    style: TextStyle(fontSize: 11, color: ChaloColors.textDisabled),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 14, color: ChaloColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF242C33), Color(0xFF1C2228)],
        ),
        border: Border(top: BorderSide(color: ChaloColors.borderShine, width: 0.5)),
      ),
      child: Row(
        children: [
          _NavItem(icon: Icons.home_outlined, label: 'Home', active: true),
          _NavItem(icon: Icons.explore_outlined, label: 'Discover', active: false),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _NavItem({required this.icon, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: active ? ChaloColors.primary : ChaloColors.textDisabled),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? ChaloColors.primary : ChaloColors.textDisabled,
            ),
          ),
        ],
      ),
    );
  }
}
