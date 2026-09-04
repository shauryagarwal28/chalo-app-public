import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'home_screen.dart';
import 'post_ride_rating_rider_screen.dart';
import 'report_incident_screen.dart';

/// The shared reason list for Community Mode's rider-initiated "I'm Not
/// Coming" control, locked in `product/decisions/12-rider-initiated-leave.md`.
/// This is the only surface this list applies to — Active Ride Mode's S9
/// Leave Party is explicitly unchanged, see that decision doc's "Scope
/// Reversal" section.
const List<String> kNotComingReasons = [
  'Plans changed / no longer going',
  'Bike trouble / mechanical issue',
  'Feeling unwell',
  "Pace doesn't match the group",
  'Feeling unsafe or uncomfortable',
];
const String kNotComingOtherReason = 'Other';

/// Rider-facing "ride in progress" placeholder. Mirrors ride_day_screen.dart's
/// header/list pattern but has none of the organiser-only attendance-marking
/// UI — a rider just sees who else is on the ride and can end it (demo-only,
/// no backend "ride actually started/ended" signal exists yet).
///
/// **2026-08-19**: also where Community Mode's new rider-initiated "I'm Not
/// Coming" control lives (pre-ride case only — see
/// `product/decisions/12-rider-initiated-leave.md` and
/// `product/features/community-mode.md`'s "Ride Day — Rider Side"). This
/// screen doesn't model an actual pre-ride vs. ride-started distinction
/// today (there's no separate "Start Ride" moment on the rider side), so
/// "I'm Not Coming" and "End Ride (mock)" are simply both offered here as
/// separate demo affordances, same as the rest of this screen's mock-data
/// standard.
class RiderRideDayScreen extends StatefulWidget {
  final String rideName;
  final String organiserName;
  final List<String> otherRiders;

  const RiderRideDayScreen({
    super.key,
    required this.rideName,
    required this.organiserName,
    required this.otherRiders,
  });

  @override
  State<RiderRideDayScreen> createState() => _RiderRideDayScreenState();
}

class _RiderRideDayScreenState extends State<RiderRideDayScreen> {
  Future<void> _showNotComingSheet() async {
    // `null` = sheet dismissed without confirming (tap outside/drag down) —
    // no action taken. `''` = confirmed with no reason given. Any other
    // string = confirmed with that reason. This is the same
    // "optional, never blocks" contract as the reason list's own spec.
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _NotComingSheet(),
    );

    if (result == null || !mounted) return;
    _confirmNotComing(reason: result.isEmpty ? null : result);
  }

  /// Pre-ride decline only (per `product/decisions/12-rider-initiated-leave.md`'s
  /// "Pre-Ride Decline — Roster and Slot Impact"): zero penalty, full roster
  /// removal, slot reopens automatically. This screen's mock data has no
  /// capacity/roster infrastructure to actually decrement against (S14/S15
  /// are still hardcoded mock cards, per `process/build-status.md`), so
  /// slot-reopening isn't shown here — just the rider-facing confirmation
  /// and exit. Cross-screen visibility (a ride chat system message on S17,
  /// a "Not Coming" state on the organiser's S16) is spec-only, not built —
  /// see the file-level note in this screen's docs update for why.
  void _confirmNotComing({String? reason}) {
    final message = reason == null
        ? "You're marked as not coming (mock, no backend yet)"
        : "You're marked as not coming — $reason (mock, no backend yet)";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

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
                  Expanded(
                    child: Text(widget.rideName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportIncidentScreen(
                          rideName: widget.rideName,
                          riders: widget.otherRiders,
                          organiserName: widget.organiserName,
                        ),
                      ),
                    ),
                    child: MetallicCard(
                      borderRadius: BorderRadius.circular(12),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.flag_outlined, color: ChaloColors.textSecondary, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Organised by ${widget.organiserName}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: ChaloColors.textSecondary.withOpacity(0.9)),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: widget.otherRiders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final name = widget.otherRiders[i];
                  return MetallicCard(
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ChaloColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _showNotComingSheet,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade400),
                      icon: Icon(Icons.event_busy_outlined, size: 18, color: Colors.red.shade400),
                      label: const Text("I'm Not Coming"),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PostRideRatingRiderScreen(
                              organiserName: widget.organiserName,
                              otherRiders: widget.otherRiders,
                            ),
                          ),
                        );
                      },
                      child: const Text('End Ride (mock)'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reason picker for "I'm Not Coming". Single-select chip list from the
/// locked 6-item reason list, plus optional free text for "Other". The
/// reason is optional and never blocks the action — "Skip" and "Confirm"
/// (with nothing selected) are two equally-weighted, equally-styled paths
/// to the exact same outcome, per the decision doc's explicit requirement
/// that skipping not read as the unusual choice.
class _NotComingSheet extends StatefulWidget {
  const _NotComingSheet();

  @override
  State<_NotComingSheet> createState() => _NotComingSheetState();
}

class _NotComingSheetState extends State<_NotComingSheet> {
  String? _selected;
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  void _toggle(String reason) {
    setState(() => _selected = _selected == reason ? null : reason);
  }

  String? _resolvedReason() {
    if (_selected == null) return null;
    if (_selected == kNotComingOtherReason) {
      final text = _otherController.text.trim();
      return text.isEmpty ? kNotComingOtherReason : text;
    }
    return _selected;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: ChaloColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ChaloColors.borderShine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "I'm Not Coming",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              "Let the organiser know why, if you'd like. Totally optional — you can skip this and still confirm.",
              style: TextStyle(fontSize: 13, color: ChaloColors.textSecondary),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ...kNotComingReasons.map(_reasonChip),
                _reasonChip(kNotComingOtherReason),
              ],
            ),
            if (_selected == kNotComingOtherReason) ...[
              const SizedBox(height: 14),
              MetallicCard(
                borderRadius: BorderRadius.circular(14),
                child: TextField(
                  controller: _otherController,
                  maxLength: 140,
                  style: const TextStyle(color: ChaloColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Say a bit more (optional)',
                    hintStyle: TextStyle(color: ChaloColors.textDisabled),
                    border: InputBorder.none,
                    counterStyle: TextStyle(color: ChaloColors.textDisabled),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _resolvedReason() ?? ''),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _reasonChip(String reason) {
    final isSelected = _selected == reason;
    return GestureDetector(
      onTap: () => _toggle(reason),
      child: MetallicCard(
        borderRadius: BorderRadius.circular(12),
        hasOrangeAccent: isSelected,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shadows: isSelected ? [BoxShadow(color: ChaloColors.primary.withOpacity(0.25), blurRadius: 10)] : null,
        child: Text(
          reason,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? ChaloColors.primary : ChaloColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
