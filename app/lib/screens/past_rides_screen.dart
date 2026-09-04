import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'report_incident_screen.dart';

/// The viewing rider's role on a given past ride — per
/// `product/decisions/13-incident-reporting.md`'s "New Scope Surfaced:
/// Reporting After Leaving a Ride," S19d's list covers every ride the rider
/// has ever been part of "as organiser, approved rider, pre-ride decliner,
/// or mid-ride leaver."
enum _PastRideRole { organiser, approvedRider, preRideDecliner, midRideLeaver }

String _roleLabel(_PastRideRole role) {
  switch (role) {
    case _PastRideRole.organiser:
      return 'Organiser';
    case _PastRideRole.approvedRider:
      return 'Approved Rider';
    case _PastRideRole.preRideDecliner:
      return 'Declined Pre-Ride';
    case _PastRideRole.midRideLeaver:
      return 'Left Mid-Ride';
  }
}

class _PastRide {
  final String route;
  final String date;
  final _PastRideRole role;

  /// The ride's other approved riders (excluding the viewer), passed to
  /// `ReportIncidentScreen` as its `riders` param — same convention
  /// `rider_ride_day_screen.dart`'s `otherRiders` already uses.
  final List<String> riders;

  /// The ride's organiser, or null when the viewer *was* the organiser
  /// (can't report yourself — same rule `ride_day_screen.dart`'s organiser
  /// side already follows by omitting `organiserName`).
  final String? organiserName;

  const _PastRide({
    required this.route,
    required this.date,
    required this.role,
    required this.riders,
    this.organiserName,
  });
}

/// S19d, "Past Rides (Report Access)" — a private, self-only list of every
/// ride the rider has ever been part of, sorted most-recent-first, with no
/// bounded time window. Exists solely so a rider who's already left a ride
/// (and lost access to `ride_chat_screen.dart`/`ride_day_screen.dart`/
/// `rider_ride_day_screen.dart`, piece 1's only entry points) has a way to
/// pick that ride and file a "Report an Incident." Deliberately not a
/// general ride-history/travel-log feature — no filters, tabs, or
/// ride-detail sub-pages; tapping a row hands off straight into the
/// existing `report_incident_screen.dart` form, unchanged, passed that
/// ride's own mock roster.
///
/// Reachable only from S19 (own profile) via a new, separate entry point —
/// not the profile's existing ride-count stat, which stays inert per spec.
/// See `product/decisions/13-incident-reporting.md`'s "New Scope Surfaced:
/// Reporting After Leaving a Ride" and `product/features/community-mode.md`'s
/// "Reporting After Leaving a Ride — S19d."
///
/// Mock data only, no time cutoff modeled or needed — same UI-shell/mock
/// standard as the rest of Community Mode (S11–S20).
class PastRidesScreen extends StatelessWidget {
  const PastRidesScreen({super.key});

  static const List<_PastRide> _pastRides = [
    _PastRide(
      route: 'Bengaluru → Coorg',
      date: '20 Aug 2026',
      role: _PastRideRole.organiser,
      riders: ['Vikram Singh', 'Neha Kapoor'],
      // organiserName omitted — the viewer organised this ride.
    ),
    _PastRide(
      route: 'Mysore → Ooty',
      date: '10 Aug 2026',
      role: _PastRideRole.midRideLeaver,
      riders: ['Suresh Kumar'],
      organiserName: 'Priya Verma',
    ),
    _PastRide(
      route: 'Bengaluru → Nandi Hills',
      date: '28 Jul 2026',
      role: _PastRideRole.preRideDecliner,
      riders: ['Vikram Singh'],
      organiserName: 'Arjun Mehta',
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
                      child: const SizedBox(width: 40, height: 40, child: Icon(Icons.arrow_back_ios_new, color: ChaloColors.textSecondary, size: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Past Rides', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                        Text('Pick a ride to report an incident from', style: TextStyle(fontSize: 12, color: ChaloColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _pastRides.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, i) {
                  final ride = _pastRides[i];
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportIncidentScreen(
                          rideName: ride.route,
                          riders: ride.riders,
                          organiserName: ride.organiserName,
                        ),
                      ),
                    ),
                    child: MetallicCard(
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ride.route, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                                  const SizedBox(height: 6),
                                  Text(ride.date, style: const TextStyle(fontSize: 12, color: ChaloColors.textSecondary)),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: ChaloColors.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                      _roleLabel(ride.role).toUpperCase(),
                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: ChaloColors.primary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right, color: ChaloColors.textSecondary),
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
