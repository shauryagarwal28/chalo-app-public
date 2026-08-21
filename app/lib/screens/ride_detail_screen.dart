import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/colors.dart';
import '../services/mock_user_state.dart';
import '../widgets/metallic_card.dart';
import '../widgets/star_rating.dart';
import 'join_point_picker_screen.dart';
import 'kyc_upload_screen.dart';
import 'other_rider_profile_screen.dart';

class RideDetailScreen extends StatelessWidget {
  final String rideName;
  final String organiserName;
  final double organiserRating;
  final String route;
  final String meetPoint;
  final DateTime date;
  final int slotsTotal;
  final int slotsFilled;
  final double minRating;

  const RideDetailScreen({
    super.key,
    required this.rideName,
    required this.organiserName,
    required this.organiserRating,
    required this.route,
    required this.meetPoint,
    required this.date,
    required this.slotsTotal,
    required this.slotsFilled,
    required this.minRating,
  });

  @override
  Widget build(BuildContext context) {
    final slotsLeft = slotsTotal - slotsFilled;
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: Column(
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: GoogleMap(
                      initialCameraPosition: const CameraPosition(target: LatLng(12.9716, 77.5946), zoom: 11),
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      polylines: {
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: const [LatLng(12.9716, 77.5946), LatLng(13.0200, 77.6100), LatLng(13.0800, 77.6400)],
                          color: ChaloColors.primary,
                          width: 4,
                        ),
                      },
                    ),
                  ),
                ),
                // Scrim behind the status bar so its (light) icons stay
                // legible over light map tiles — scoped to this map screen
                // only, not a global status-bar brightness change.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).padding.top,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.45),
                            Colors.black.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: SafeArea(
                    bottom: false,
                    child: GestureDetector(
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
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rideName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ChaloColors.textPrimary)),
                  const SizedBox(height: 6),
                  Text(route, style: const TextStyle(fontSize: 14, color: ChaloColors.textSecondary)),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OtherRiderProfileScreen(name: organiserName, bike: 'Royal Enfield Classic 350'),
                      ),
                    ),
                    child: MetallicCard(
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ChaloColors.bgElevated,
                                border: Border.all(color: ChaloColors.borderShine),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.person_outline, color: ChaloColors.textSecondary),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(organiserName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      StarRatingDisplay(rating: organiserRating),
                                      const SizedBox(width: 10),
                                      const VerifiedBadge(),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: ChaloColors.textSecondary, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  MetallicCard(
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _DetailRow(icon: Icons.calendar_today_outlined, label: 'Date', value: _formatDate(date)),
                          const SizedBox(height: 12),
                          _DetailRow(icon: Icons.location_on_outlined, label: 'Meet at', value: meetPoint),
                          const SizedBox(height: 12),
                          _DetailRow(icon: Icons.people_outline, label: 'Slots', value: '$slotsLeft of $slotsTotal left'),
                          const SizedBox(height: 12),
                          _DetailRow(icon: Icons.star_border_rounded, label: 'Min. rating', value: minRating.toStringAsFixed(1)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: ElevatedButton(
                onPressed: slotsLeft <= 0
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MockUserState.isVerified
                                ? JoinPointPickerScreen(rideName: rideName)
                                : const KycUploadScreen(),
                          ),
                        ),
                child: Text(slotsLeft <= 0 ? 'Ride Full' : 'Join This Ride'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ChaloColors.primary),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13, color: ChaloColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
