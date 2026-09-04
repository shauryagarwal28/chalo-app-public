import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';

/// A single selectable target in the "who are you reporting" picker.
/// Reporting is fully symmetric (`product/decisions/13-incident-reporting.md`
/// — "Reporting Is Symmetric (Organiser Included)"): the organiser is a
/// selectable target exactly like any other rider, so this deliberately
/// doesn't reuse S15/S16's rider-only roster model.
class _ReportTarget {
  final String name;
  final bool isOrganiser;

  const _ReportTarget(this.name, {this.isOrganiser = false});
}

/// On-ride incident reporting form (Decision 13, piece 1 — "the on-ride
/// reporting flow" only; reporting after leaving a ride is separate,
/// unbuilt scope — see `process/build-status.md` item 32).
///
/// Reachable from `ride_chat_screen.dart` (S17, primary anchor),
/// `ride_day_screen.dart` (S16, organiser side), and
/// `rider_ride_day_screen.dart` (rider side) via a header icon button,
/// matching S17's existing header-icon pattern.
///
/// **Photo attachment is fully mocked, by deliberate architecture call**
/// (senior-engineer, 2026-08-31): no `image_picker` or any other new native
/// dependency was added. "Attach Photo" just appends a placeholder chip to
/// a local list — no real camera/gallery access, no real file, nothing
/// leaves the device. See `docs/technical/decisions/` for the full
/// tradeoff writeup. This matches the phase-gate note in
/// `product/features/community-mode.md`'s "Report an Incident" section:
/// Community Mode stays UI-shell-only, no real photo upload backend or
/// storage exists to receive a real file anyway.
///
/// Stays inside the existing "(mock, no backend yet)" convention:
/// Submit shows a SnackBar and pops back to wherever this was opened from —
/// no real complaint storage, no real review queue, nothing wired to a
/// backend.
class ReportIncidentScreen extends StatefulWidget {
  final String rideName;

  /// Every approved rider on the ride, excluding whoever is viewing this
  /// screen (same convention `rider_ride_day_screen.dart`'s `otherRiders`
  /// already uses).
  final List<String> riders;

  /// The ride's organiser, shown as a selectable target alongside
  /// `riders` — omit (leave null) when the viewer *is* the organiser,
  /// since you can't report yourself.
  final String? organiserName;

  const ReportIncidentScreen({
    super.key,
    required this.rideName,
    required this.riders,
    this.organiserName,
  });

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  late final List<_ReportTarget> _targets = [
    ...widget.riders.map((r) => _ReportTarget(r)),
    if (widget.organiserName != null) _ReportTarget(widget.organiserName!, isOrganiser: true),
  ];

  String? _selectedTarget;
  final _descriptionController = TextEditingController();
  int _attachedPhotoCount = 0;

  static const int _maxPhotos = 3;

  bool get _canSubmit => _selectedTarget != null && _descriptionController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _addMockPhoto() {
    if (_attachedPhotoCount >= _maxPhotos) return;
    setState(() => _attachedPhotoCount++);
  }

  void _removeMockPhoto(int index) {
    setState(() => _attachedPhotoCount--);
  }

  void _submit() {
    if (!_canSubmit) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Report submitted against $_selectedTarget (mock, no backend yet)')),
    );
    Navigator.pop(context);
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Report an Incident', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                        Text(widget.rideName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: ChaloColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                children: [
                  const Text('Who are you reporting?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _targets.map(_targetChip).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text('What happened?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                  const SizedBox(height: 10),
                  MetallicCard(
                    borderRadius: BorderRadius.circular(14),
                    child: TextField(
                      controller: _descriptionController,
                      maxLines: 6,
                      minLines: 4,
                      maxLength: 500,
                      style: const TextStyle(color: ChaloColors.textPrimary, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Describe what happened, as much detail as you can share',
                        hintStyle: TextStyle(color: ChaloColors.textDisabled),
                        border: InputBorder.none,
                        counterStyle: TextStyle(color: ChaloColors.textDisabled),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Attach photos (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                  const SizedBox(height: 4),
                  const Text(
                    'Proof helps a review move faster.',
                    style: TextStyle(fontSize: 12, color: ChaloColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (int i = 0; i < _attachedPhotoCount; i++) _photoChip(i),
                      if (_attachedPhotoCount < _maxPhotos)
                        GestureDetector(
                          onTap: _addMockPhoto,
                          child: MetallicCard(
                            borderRadius: BorderRadius.circular(12),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 16, color: ChaloColors.textSecondary),
                                SizedBox(width: 6),
                                Text('Attach Photo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Your identity is never shared with the person you report.',
                    style: TextStyle(fontSize: 12, color: ChaloColors.textSecondary.withOpacity(0.9), fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _canSubmit ? _submit : null,
                        child: const Text('Submit'),
                      ),
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

  Widget _targetChip(_ReportTarget target) {
    final isSelected = _selectedTarget == target.name;
    return GestureDetector(
      onTap: () => setState(() => _selectedTarget = isSelected ? null : target.name),
      child: MetallicCard(
        borderRadius: BorderRadius.circular(12),
        hasOrangeAccent: isSelected,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shadows: isSelected ? [BoxShadow(color: ChaloColors.primary.withOpacity(0.25), blurRadius: 10)] : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                target.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? ChaloColors.primary : ChaloColors.textSecondary,
                ),
              ),
            ),
            if (target.isOrganiser) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: ChaloColors.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('ORGANISER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: ChaloColors.primary)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoChip(int index) {
    return MetallicCard(
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, size: 16, color: ChaloColors.textSecondary),
          const SizedBox(width: 6),
          Text('Photo ${index + 1}', style: const TextStyle(fontSize: 13, color: ChaloColors.textSecondary)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _removeMockPhoto(index),
            child: const Icon(Icons.close, size: 14, color: ChaloColors.textDisabled),
          ),
        ],
      ),
    );
  }
}
