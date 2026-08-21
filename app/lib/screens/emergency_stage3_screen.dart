import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';

class EmergencyStage3Screen extends StatelessWidget {
  final String riderName;

  /// Null when the server has no cached location for the stopped rider at
  /// all (`emergency:full_alert`'s `lat`/`lng` were both null on the wire —
  /// see emergency.ts's `fireFullAlert`). The demo path always passes a
  /// human-readable place name; the real path passes formatted
  /// coordinates instead (this app has no reverse-geocoding), never a
  /// fabricated place name.
  final String? lastKnownLocation;

  /// Null for the demo path (it never had this field to pass). Real
  /// payload's `stoppedAt` (ISO-8601, per system-overview.md's Event Map).
  final DateTime? stoppedAt;

  final Duration timeElapsed;

  /// Null when the server couldn't compute a distance — no other party
  /// member has a cached location to compare against (see emergency.ts's
  /// `computeDistanceBehindKm` doc comment). Never substituted with a fake
  /// 0.0 — displayed as "Unknown" instead.
  final double? distanceBehindKm;

  const EmergencyStage3Screen({
    super.key,
    required this.riderName,
    required this.lastKnownLocation,
    this.stoppedAt,
    required this.timeElapsed,
    required this.distanceBehindKm,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = timeElapsed.inMinutes;
    final seconds = timeElapsed.inSeconds % 60;
    final stoppedAtLocal = stoppedAt?.toLocal();
    final stoppedAtLabel = stoppedAtLocal != null
        ? '${stoppedAtLocal.hour.toString().padLeft(2, '0')}:${stoppedAtLocal.minute.toString().padLeft(2, '0')}'
        : null;
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.error, color: Colors.redAccent, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$riderName may need help',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ChaloColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: ChaloColors.textSecondary, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              MetallicCard(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 180,
                  alignment: Alignment.center,
                  child: const Icon(Icons.map_outlined, size: 48, color: ChaloColors.textDisabled),
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Last known location — mini-map not wired yet',
                    style: TextStyle(fontSize: 11, color: ChaloColors.textDisabled),
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
                      _InfoRow(label: 'Last known location', value: lastKnownLocation ?? 'Unknown'),
                      if (stoppedAtLabel != null) ...[
                        const SizedBox(height: 10),
                        _InfoRow(label: 'Time of stop', value: stoppedAtLabel),
                      ],
                      const SizedBox(height: 10),
                      _InfoRow(label: 'Time elapsed', value: '${minutes}m ${seconds}s'),
                      const SizedBox(height: 10),
                      _InfoRow(
                        label: 'Distance behind group',
                        value: distanceBehindKm != null
                            ? '${distanceBehindKm!.toStringAsFixed(1)} km'
                            : 'Unknown',
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.podcasts),
                        label: const Text('Radio'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.call),
                        label: const Text('Call'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13, color: ChaloColors.textSecondary)),
        ),
        const SizedBox(width: 8),
        // Wrapped in Flexible + ellipsis: `value` used to always be a short
        // demo string, but the real payload can now put a formatted
        // "lat, lng" coordinate pair here (no reverse-geocoding in this
        // app) — this codebase's recurring Row/Text overflow bug
        // (party_ready_screen.dart, waiting_room_screen.dart,
        // home_screen.dart) if left unguarded.
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
