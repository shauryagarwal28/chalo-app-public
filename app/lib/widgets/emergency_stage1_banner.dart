import 'package:flutter/material.dart';
import '../theme/colors.dart';
import 'metallic_card.dart';

class EmergencyStage1Banner extends StatelessWidget {
  final String riderName;

  /// Null when there's no live countdown to show — the real
  /// `emergency:stage1` wire event (`{ stoppedUserId, stoppedUserName }`,
  /// per system-overview.md's Event Map) does not carry a countdown value
  /// at all (only `emergency:confirm`, sent to the stopped rider only,
  /// does). Rather than fabricating a number client-side by hardcoding the
  /// confirmation-window default (which technical/systems/
  /// emergency-detection.md explicitly says must stay server-tunable, not
  /// duplicated in the app), the real trigger path passes null here and
  /// this widget falls back to a countdown-free message. The demo trigger
  /// path still passes a real locally-ticking int, unaffected.
  final int? secondsRemaining;

  const EmergencyStage1Banner({
    super.key,
    required this.riderName,
    this.secondsRemaining,
  });

  @override
  Widget build(BuildContext context) {
    return MetallicCard(
      hasOrangeAccent: true,
      borderRadius: BorderRadius.circular(16),
      shadows: [
        BoxShadow(color: ChaloColors.primary.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 4)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: ChaloColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                secondsRemaining != null
                    ? '$riderName may have stopped — ${secondsRemaining}s confirmation'
                    : '$riderName may have stopped — awaiting confirmation',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ChaloColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
