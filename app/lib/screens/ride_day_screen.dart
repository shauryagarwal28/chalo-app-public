import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'post_ride_rating_organiser_screen.dart';

enum _Attendance { pending, present, absent }

class _MockRider {
  final String name;
  final String joinPoint;
  _Attendance attendance;

  _MockRider({required this.name, required this.joinPoint, this.attendance = _Attendance.pending});
}

class RideDayScreen extends StatefulWidget {
  final String rideName;

  const RideDayScreen({super.key, required this.rideName});

  @override
  State<RideDayScreen> createState() => _RideDayScreenState();
}

class _RideDayScreenState extends State<RideDayScreen> {
  final List<_MockRider> _riders = [
    _MockRider(name: 'Vikram Singh', joinPoint: 'Hebbal Flyover'),
    _MockRider(name: 'Neha Kapoor', joinPoint: 'Yelahanka Junction'),
    _MockRider(name: 'Suresh Kumar', joinPoint: 'Meetup point'),
  ];

  bool _rideStarted = false;

  bool get _allResolved => _riders.every((r) => r.attendance != _Attendance.pending);

  @override
  Widget build(BuildContext context) {
    final presentCount = _riders.where((r) => r.attendance == _Attendance.present).length;
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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Auto-marked Absent 30 min after departure if not confirmed Present',
                  style: TextStyle(fontSize: 12, color: ChaloColors.textSecondary.withOpacity(0.9)),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _riders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final r = _riders[i];
                  return MetallicCard(
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ChaloColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(r.joinPoint, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ChaloColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          _AttendanceToggle(
                            value: r.attendance,
                            onChanged: (v) => setState(() => r.attendance = v),
                          ),
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
                child: _rideStarted
                    ? ElevatedButton(
                        onPressed: () {
                          final presentNames = _riders
                              .where((r) => r.attendance == _Attendance.present)
                              .map((r) => r.name)
                              .toList();
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => PostRideRatingOrganiserScreen(riders: presentNames)),
                          );
                        },
                        child: const Text('End Ride'),
                      )
                    : ElevatedButton(
                        onPressed: !_allResolved || presentCount == 0
                            ? null
                            : () {
                                setState(() => _rideStarted = true);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Live party started for $presentCount riders (mock)')),
                                );
                              },
                        child: Text(_allResolved ? 'Start Ride ($presentCount present)' : 'Mark all riders first'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceToggle extends StatelessWidget {
  final _Attendance value;
  final ValueChanged<_Attendance> onChanged;

  const _AttendanceToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip('Present', _Attendance.present, Colors.greenAccent),
        const SizedBox(width: 6),
        _chip('Absent', _Attendance.absent, Colors.redAccent),
      ],
    );
  }

  Widget _chip(String label, _Attendance target, Color color) {
    final selected = value == target;
    return GestureDetector(
      onTap: () => onChanged(target),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : Colors.transparent,
          border: Border.all(color: selected ? color : ChaloColors.borderShine),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? color : ChaloColors.textSecondary)),
      ),
    );
  }
}
