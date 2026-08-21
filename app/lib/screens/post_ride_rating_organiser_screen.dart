import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import '../widgets/star_rating.dart';

class PostRideRatingOrganiserScreen extends StatefulWidget {
  final List<String> riders;

  const PostRideRatingOrganiserScreen({super.key, required this.riders});

  @override
  State<PostRideRatingOrganiserScreen> createState() => _PostRideRatingOrganiserScreenState();
}

class _PostRideRatingOrganiserScreenState extends State<PostRideRatingOrganiserScreen> {
  late final Map<String, double> _ratings = {for (final r in widget.riders) r: 0};

  int get _ratedCount => _ratings.values.where((v) => v > 0).length;
  bool get _allRated => _ratedCount == widget.riders.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rate All Riders', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: widget.riders.isEmpty ? 0 : _ratedCount / widget.riders.length,
                      minHeight: 8,
                      backgroundColor: ChaloColors.bgElevated,
                      valueColor: const AlwaysStoppedAnimation(ChaloColors.primary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('$_ratedCount of ${widget.riders.length} rated', style: const TextStyle(fontSize: 12, color: ChaloColors.textSecondary)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: widget.riders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final name = widget.riders[i];
                  return MetallicCard(
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(name, style: const TextStyle(color: ChaloColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 10),
                          InteractiveStarRating(rating: _ratings[name]!, onChanged: (v) => setState(() => _ratings[name] = v)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: ElevatedButton(
                  onPressed: _allRated
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('All ratings submitted (mock) — no backend yet')),
                          );
                          Navigator.of(context).pop();
                        }
                      : null,
                  child: Text(_allRated ? 'Submit' : 'Rate everyone to submit'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
