import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/mock_user_state.dart';
import '../widgets/metallic_card.dart';
import '../widgets/star_rating.dart';
import 'kyc_upload_screen.dart';
import 'post_a_ride_screen.dart';
import 'ride_detail_screen.dart';

class _MockRide {
  final String rideName;
  final String organiserName;
  final double organiserRating;
  final String route;
  final String meetPoint;
  final DateTime date;
  final int slotsTotal;
  final int slotsFilled;
  final double minRating;

  const _MockRide({
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
}

class DiscoverRidesScreen extends StatelessWidget {
  const DiscoverRidesScreen({super.key});

  void _onPostARide(BuildContext context) {
    if (MockUserState.isVerified) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PostARideScreen()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const KycUploadScreen()));
    }
  }

  static final _rides = [
    _MockRide(
      rideName: 'Nandi Hills Sunrise Run',
      organiserName: 'Arjun Mehta',
      organiserRating: 4.6,
      route: 'Bangalore → Nandi Hills',
      meetPoint: 'Hebbal Flyover, Bangalore',
      date: DateTime.now().add(const Duration(days: 2)),
      slotsTotal: 8,
      slotsFilled: 5,
      minRating: 4.0,
    ),
    _MockRide(
      rideName: 'Delhi-Rishikesh Highway Cruise',
      organiserName: 'Priya Nair',
      organiserRating: 4.8,
      route: 'Delhi → Rishikesh',
      meetPoint: 'Akshardham, Delhi',
      date: DateTime.now().add(const Duration(days: 5)),
      slotsTotal: 12,
      slotsFilled: 12,
      minRating: 4.0,
    ),
    _MockRide(
      rideName: 'Weekend Ghat Ride',
      organiserName: 'Rahul Sharma',
      organiserRating: 4.2,
      route: 'Pune → Lonavala',
      meetPoint: 'Katraj Tunnel, Pune',
      date: DateTime.now().add(const Duration(days: 3)),
      slotsTotal: 6,
      slotsFilled: 2,
      minRating: 3.5,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                    child: Text('Discover Rides', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                  ),
                  GestureDetector(
                    onTap: () => _onPostARide(context),
                    child: MetallicCard(
                      borderRadius: BorderRadius.circular(12),
                      hasOrangeAccent: true,
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.add, color: ChaloColors.primary, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: MetallicCard(
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: ChaloColors.textSecondary, size: 18),
                      SizedBox(width: 10),
                      Text('Search by route (e.g. Delhi → Agra)', style: TextStyle(color: ChaloColors.textSecondary, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: _rides.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, i) {
                  final ride = _rides[i];
                  final slotsLeft = ride.slotsTotal - ride.slotsFilled;
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RideDetailScreen(
                          rideName: ride.rideName,
                          organiserName: ride.organiserName,
                          organiserRating: ride.organiserRating,
                          route: ride.route,
                          meetPoint: ride.meetPoint,
                          date: ride.date,
                          slotsTotal: ride.slotsTotal,
                          slotsFilled: ride.slotsFilled,
                          minRating: ride.minRating,
                        ),
                      ),
                    ),
                    child: MetallicCard(
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ride.rideName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                                  ),
                                ),
                                StarRatingDisplay(rating: ride.organiserRating, size: 13),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(ride.route, style: const TextStyle(fontSize: 13, color: ChaloColors.textSecondary)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.person_outline, size: 14, color: ChaloColors.textSecondary.withOpacity(0.8)),
                                const SizedBox(width: 6),
                                Flexible(child: Text(ride.organiserName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: ChaloColors.textSecondary))),
                                const Spacer(),
                                Text(
                                  slotsLeft <= 0 ? 'Full' : '$slotsLeft of ${ride.slotsTotal} left',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: slotsLeft <= 0 ? ChaloColors.textDisabled : ChaloColors.primary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
