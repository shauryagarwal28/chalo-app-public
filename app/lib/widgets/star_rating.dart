import 'package:flutter/material.dart';
import '../theme/colors.dart';

class StarRatingDisplay extends StatelessWidget {
  final double rating;
  final double size;

  const StarRatingDisplay({super.key, required this.rating, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, color: ChaloColors.primary, size: size),
        SizedBox(width: size * 0.25),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(fontSize: size * 0.9, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
        ),
      ],
    );
  }
}

class NewRiderBadge extends StatelessWidget {
  const NewRiderBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: ChaloColors.primary),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'New Rider',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ChaloColors.primary),
      ),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified, size: 14, color: Colors.lightBlueAccent),
        SizedBox(width: 4),
        Text('Verified', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.lightBlueAccent)),
      ],
    );
  }
}

class InteractiveStarRating extends StatelessWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final double size;

  const InteractiveStarRating({
    super.key,
    required this.rating,
    required this.onChanged,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return GestureDetector(
          onTap: () => onChanged((i + 1).toDouble()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              color: ChaloColors.primary,
              size: size,
            ),
          ),
        );
      }),
    );
  }
}
