import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'rider_ride_day_screen.dart';

class JoinPointPickerScreen extends StatefulWidget {
  final String rideName;

  const JoinPointPickerScreen({super.key, required this.rideName});

  @override
  State<JoinPointPickerScreen> createState() => _JoinPointPickerScreenState();
}

class _JoinPointPickerScreenState extends State<JoinPointPickerScreen> {
  static const _routePoints = [
    LatLng(12.9716, 77.5946),
    LatLng(13.0200, 77.6100),
    LatLng(13.0800, 77.6400),
  ];

  LatLng? _pin;

  void _onMapTap(LatLng point) {
    setState(() => _pin = point);
  }

  void _confirm() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Join request submitted (mock) — no backend yet')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _routePoints[0], zoom: 12),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              onTap: _onMapTap,
              polylines: {
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: _routePoints,
                  color: ChaloColors.primary,
                  width: 4,
                ),
              },
              markers: {
                if (_pin != null)
                  Marker(
                    markerId: const MarkerId('join_point'),
                    position: _pin!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                    infoWindow: const InfoWindow(title: 'Your join point'),
                  ),
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: MetallicCard(
                        borderRadius: BorderRadius.circular(12),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.close, color: ChaloColors.textSecondary, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetallicCard(
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.search, color: ChaloColors.textSecondary, size: 18),
                              SizedBox(width: 10),
                              Text('Search along the route', style: TextStyle(color: ChaloColors.textSecondary, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MetallicCard(
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: ChaloColors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _pin == null
                                  ? 'Tap anywhere on the route to drop your join point'
                                  : 'Join point set — forward-only, cannot join behind the start',
                              style: const TextStyle(fontSize: 12, color: ChaloColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _pin == null ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _pin == null ? ChaloColors.bgCard : ChaloColors.primary,
                      disabledBackgroundColor: ChaloColors.bgCard,
                      disabledForegroundColor: ChaloColors.textDisabled,
                    ),
                    child: const Text('Confirm Join Point'),
                  ),
                  const SizedBox(height: 12),
                  // No backend yet to signal "ride day arrived and you were
                  // approved" — demo-only trigger, same pattern as
                  // waiting_room_screen.dart's "Simulate: Host Started Ride".
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RiderRideDayScreen(
                          rideName: widget.rideName,
                          organiserName: 'Ride Organiser',
                          otherRiders: const ['Vikram Singh', 'Neha Kapoor', 'Suresh Kumar'],
                        ),
                      ),
                    ),
                    child: const Text('Simulate: Ride Day Started (demo only)'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
