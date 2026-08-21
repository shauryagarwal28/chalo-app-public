import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../services/api_exception.dart';
import '../services/mock_user_state.dart';
import '../services/user_service.dart';
import '../widgets/metallic_card.dart';
import 'home_screen.dart';

/// Letters, spaces, hyphens, and apostrophes — covers names like
/// "Anne-Marie" or "O'Brien" while still blocking digits/symbols/emoji.
final _nameCharPattern = RegExp(r"[a-zA-Z '-]");

class ProfileCreationScreen extends StatefulWidget {
  final String? prefillName;
  final String? prefillPhotoUrl;

  const ProfileCreationScreen({
    super.key,
    this.prefillName,
    this.prefillPhotoUrl,
  });

  @override
  State<ProfileCreationScreen> createState() => _ProfileCreationScreenState();
}

class _ProfileCreationScreenState extends State<ProfileCreationScreen> {
  late final TextEditingController _nameController;
  final TextEditingController _bikeController = TextEditingController();
  final Set<String> _selectedRideTypes = {};

  static const List<Map<String, String>> _rideTypes = [
    {'id': 'highway', 'label': 'Highway Cruising', 'icon': '🛣️'},
    {'id': 'mountain', 'label': 'Mountain / Ghats', 'icon': '⛰️'},
    {'id': 'sunrise', 'label': 'Sunrise / Early Morning', 'icon': '🌅'},
    {'id': 'weekend', 'label': 'Weekend Day Rides', 'icon': '☀️'},
    {'id': 'touring', 'label': 'Multi-Day Touring', 'icon': '🗺️'},
    {'id': 'city', 'label': 'Café Racer / City Rides', 'icon': '☕'},
    {'id': 'offroad', 'label': 'Off-Road / Dirt Tracks', 'icon': '🏕️'},
  ];

  bool get _canContinue => _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.prefillName ?? '');
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bikeController.dispose();
    super.dispose();
  }

  /// `PUT /users/me` with the entered name — see the "Let's Ride" onTap's
  /// comment for why this is fire-and-forget and never surfaces an error
  /// to the user. [name] is already trimmed and known non-empty by the
  /// caller (this method is never invoked from the Skip path, where there
  /// is no name to send — the backend already defaults new users to
  /// `name: ''`, so there's nothing to sync there).
  Future<void> _persistNameToBackend(String name) async {
    try {
      await UserService.updateName(name);
    } on ApiException catch (e) {
      debugPrint('UserService.updateName failed (non-blocking): $e');
    } catch (e) {
      debugPrint('UserService.updateName failed (non-blocking): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF232B31), Color(0xFF1A1F23), Color(0xFF141920)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Create Profile',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: ChaloColors.textPrimary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        // Skip always navigates through, regardless of
                        // field state — unlike "Let's Ride" it applies no
                        // validation. Leaves MockUserState.riderName at its
                        // default (null) rather than setting it, so
                        // home_screen.dart's greeting correctly falls back
                        // to the generic "Rider" text.
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                          (route) => false,
                        );
                      },
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 14,
                          color: ChaloColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      // Photo
                      Center(child: _PhotoPicker(photoUrl: widget.prefillPhotoUrl)),
                      const SizedBox(height: 32),

                      // Name
                      _SectionLabel('Your Name', required: true),
                      const SizedBox(height: 8),
                      _InputField(
                        controller: _nameController,
                        hint: 'Full name',
                        prefillSource: widget.prefillName != null ? 'From Google' : null,
                        inputFormatters: [FilteringTextInputFormatter.allow(_nameCharPattern)],
                      ),
                      const SizedBox(height: 24),

                      // Bike
                      _SectionLabel('Your Bike', required: false),
                      const SizedBox(height: 8),
                      _InputField(
                        controller: _bikeController,
                        hint: 'e.g. Royal Enfield Himalayan',
                      ),
                      const SizedBox(height: 32),

                      // Ride types
                      _SectionLabel('Rides You\'re Into', required: false),
                      const SizedBox(height: 4),
                      const Text(
                        'Pick as many as you like',
                        style: TextStyle(fontSize: 12, color: ChaloColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      _RideTypeGrid(
                        rideTypes: _rideTypes,
                        selected: _selectedRideTypes,
                        onToggle: (id) => setState(() {
                          _selectedRideTypes.contains(id)
                              ? _selectedRideTypes.remove(id)
                              : _selectedRideTypes.add(id);
                        }),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),

              // Continue button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: _ContinueButton(
                  enabled: _canContinue,
                  onTap: () {
                    final name = _nameController.text.trim();
                    MockUserState.riderName = name.isEmpty ? null : name;
                    // Fire-and-forget: PUT /users/me persists the name
                    // server-side (closes the "empty-name gap" documented
                    // in build-status.md/party_service.dart — every
                    // rider's server-side name was '' until now). Not
                    // awaited before navigating and any failure is
                    // swallowed here rather than surfaced, per this
                    // screen's existing behaviour of never blocking
                    // "Let's Ride" — the name is not critical-path, worst
                    // case it just stays a fallback label as it already
                    // does today. The Future itself still runs to
                    // completion in the background after this screen is
                    // popped, since Dart doesn't cancel un-awaited work.
                    unawaited(_persistNameToBackend(name));
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final String? photoUrl;
  const _PhotoPicker({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ChaloColors.bgCard,
            border: Border.all(color: ChaloColors.borderShine, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: ChaloColors.primary.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: photoUrl != null
              ? ClipOval(child: Image.network(photoUrl!, fit: BoxFit.cover))
              : const Icon(Icons.person_outline, size: 40, color: ChaloColors.textSecondary),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: ChaloColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: ChaloColors.bgApp, width: 2),
            ),
            child: const Icon(Icons.add, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool required;
  const _SectionLabel(this.label, {required this.required});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ChaloColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        if (!required) ...[
          const SizedBox(width: 6),
          const Text(
            'optional',
            style: TextStyle(fontSize: 11, color: ChaloColors.textDisabled),
          ),
        ],
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? prefillSource;
  final List<TextInputFormatter>? inputFormatters;

  const _InputField({
    required this.controller,
    required this.hint,
    this.prefillSource,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return MetallicCard(
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            inputFormatters: inputFormatters,
            style: const TextStyle(color: ChaloColors.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: ChaloColors.textDisabled, fontSize: 16),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          if (prefillSource != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 10),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 12, color: ChaloColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    prefillSource!,
                    style: const TextStyle(fontSize: 11, color: ChaloColors.primary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RideTypeGrid extends StatelessWidget {
  final List<Map<String, String>> rideTypes;
  final Set<String> selected;
  final void Function(String) onToggle;

  const _RideTypeGrid({required this.rideTypes, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: rideTypes.map((type) {
        final isSelected = selected.contains(type['id']);
        return GestureDetector(
          onTap: () => onToggle(type['id']!),
          child: MetallicCard(
            borderRadius: BorderRadius.circular(12),
            hasOrangeAccent: isSelected,
            shadows: isSelected
                ? [BoxShadow(color: ChaloColors.primary.withOpacity(0.25), blurRadius: 10)]
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(type['icon']!, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  type['label']!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? ChaloColors.primary : ChaloColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _ContinueButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [BoxShadow(color: ChaloColors.primary.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 4))]
            : [],
      ),
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? ChaloColors.primary : ChaloColors.bgCard,
          disabledBackgroundColor: ChaloColors.bgCard,
        ),
        child: Text(
          'Let\'s Ride',
          style: TextStyle(color: enabled ? Colors.white : ChaloColors.textDisabled),
        ),
      ),
    );
  }
}
