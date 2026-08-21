import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import '../widgets/star_rating.dart';
import 'home_screen.dart';

class PostRideRatingRiderScreen extends StatefulWidget {
  final String organiserName;
  final List<String> otherRiders;

  /// When true, Submit sends the rider all the way to Home
  /// (`pushAndRemoveUntil`) instead of the default `Navigator.pop`.
  ///
  /// **Added 2026-08-20** for `live_ride_screen.dart`'s mid-ride-leave
  /// immediate-rating trigger (`product/decisions/12-rider-initiated-leave.md`'s
  /// "Mid-Ride Leave — Rating Flow"): that caller reaches this screen via
  /// `pushReplacement` (so the party's live map/WS connection is gone by the
  /// time this screen shows, not just hidden underneath it), which means
  /// there's no "back" route left for a bare `pop()` to land on. The
  /// existing caller (`rider_ride_day_screen.dart`'s "End Ride (mock)",
  /// reached via its own `pushReplacement` earlier in that screen's own
  /// chain) is unaffected — it doesn't pass this, so `pop()` stays the
  /// default, unchanged behaviour.
  final bool returnToHomeOnSubmit;

  const PostRideRatingRiderScreen({
    super.key,
    required this.organiserName,
    required this.otherRiders,
    this.returnToHomeOnSubmit = false,
  });

  @override
  State<PostRideRatingRiderScreen> createState() => _PostRideRatingRiderScreenState();
}

class _PostRideRatingRiderScreenState extends State<PostRideRatingRiderScreen> {
  double _organiserRating = 0;
  late final Map<String, double> _riderRatings = {for (final r in widget.otherRiders) r: 0};

  bool get _canSubmit => _organiserRating > 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Rate This Ride', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ORGANISER · REQUIRED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ChaloColors.textSecondary, letterSpacing: 1.2)),
                    const SizedBox(height: 10),
                    MetallicCard(
                      hasOrangeAccent: true,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            Text(widget.organiserName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                            const SizedBox(height: 12),
                            InteractiveStarRating(rating: _organiserRating, onChanged: (v) => setState(() => _organiserRating = v)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('OTHER RIDERS · OPTIONAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ChaloColors.textSecondary, letterSpacing: 1.2)),
                    const SizedBox(height: 10),
                    ...widget.otherRiders.map(
                      (name) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: MetallicCard(
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ChaloColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14))),
                                InteractiveStarRating(rating: _riderRatings[name]!, size: 22, onChanged: (v) => setState(() => _riderRatings[name] = v)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: ElevatedButton(
                  onPressed: _canSubmit
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Rating submitted (mock) — no backend yet')),
                          );
                          if (widget.returnToHomeOnSubmit) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const HomeScreen()),
                              (route) => false,
                            );
                          } else {
                            Navigator.of(context).pop();
                          }
                        }
                      : null,
                  child: const Text('Submit'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
