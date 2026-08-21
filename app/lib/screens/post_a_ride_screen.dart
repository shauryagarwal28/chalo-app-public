import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'manage_approvals_screen.dart';

class PostARideScreen extends StatefulWidget {
  const PostARideScreen({super.key});

  @override
  State<PostARideScreen> createState() => _PostARideScreenState();
}

class _PostARideScreenState extends State<PostARideScreen> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _meetPointController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _rideDate;
  TimeOfDay? _rideTime;
  String? _dateTimeError;
  int _riderCap = 8;
  double _minRating = 4.0;
  bool _acceptNewRiders = false;

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _meetPointController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // Themed date/time pickers reused from create_party_screen.dart (dark/
  // orange ColorScheme, already fixed for the AM/PM contrast issue) rather
  // than inventing new picker styling — per the 2026-08-17 addendum spec in
  // product/decisions/06-11-remaining.md.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _rideDate ?? today,
      firstDate: today,
      // No real maximum — long-lead-time rides (e.g. a trip planned months
      // out) are a real use case per the spec. 10 years is a stand-in for
      // "no restriction" since showDatePicker requires some finite bound.
      lastDate: today.add(const Duration(days: 3650)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: ChaloColors.primary,
            secondary: ChaloColors.primary,
            surface: Color(0xFF242B30),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _rideDate = picked;
        _dateTimeError = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _rideTime ?? const TimeOfDay(hour: 6, minute: 0),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: ChaloColors.primary,
            secondary: ChaloColors.primary,
            surface: Color(0xFF242B30),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _rideTime = picked;
        _dateTimeError = null;
      });
    }
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  void _post() {
    if (_rideDate == null || _rideTime == null) {
      setState(() => _dateTimeError = 'Pick a date and departure time for the ride');
      return;
    }
    final departure = DateTime(_rideDate!.year, _rideDate!.month, _rideDate!.day, _rideTime!.hour, _rideTime!.minute);
    if (!departure.isAfter(DateTime.now())) {
      setState(() => _dateTimeError = 'Departure must be in the future — pick a later date or time');
      return;
    }
    setState(() => _dateTimeError = null);

    final origin = _originController.text.trim();
    final destination = _destinationController.text.trim();
    final rideName = origin.isEmpty || destination.isEmpty ? 'Your Posted Ride' : '$origin → $destination';
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride posted (mock) — no backend yet')),
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ManageApprovalsScreen(rideName: rideName)),
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
                      child: const SizedBox(width: 40, height: 40, child: Icon(Icons.close, color: ChaloColors.textSecondary, size: 18)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('Post a Ride', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('ROUTE'),
                    const SizedBox(height: 10),
                    _TextField(controller: _originController, hint: 'Starting point'),
                    const SizedBox(height: 10),
                    _TextField(controller: _destinationController, hint: 'Destination'),
                    const SizedBox(height: 20),
                    _Label('MEETUP POINT'),
                    const SizedBox(height: 10),
                    _TextField(controller: _meetPointController, hint: 'Exact address for departure'),
                    const SizedBox(height: 20),
                    _Label('DATE & DEPARTURE TIME'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _DateTimeField(
                            icon: Icons.calendar_today_outlined,
                            label: _rideDate != null ? _formatDate(_rideDate!) : 'Date',
                            isSet: _rideDate != null,
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateTimeField(
                            icon: Icons.access_time_outlined,
                            label: _rideTime != null ? _formatTime(_rideTime!) : 'Time',
                            isSet: _rideTime != null,
                            onTap: _pickTime,
                          ),
                        ),
                      ],
                    ),
                    if (_dateTimeError != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFFE05252), size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _dateTimeError!,
                              style: const TextStyle(color: Color(0xFFE05252), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    _Label('RIDER CAP: $_riderCap'),
                    const SizedBox(height: 10),
                    MetallicCard(
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: _riderCap > 4 ? () => setState(() => _riderCap--) : null,
                              icon: const Icon(Icons.remove_circle_outline, color: ChaloColors.primary),
                            ),
                            Expanded(
                              child: Text('$_riderCap riders', textAlign: TextAlign.center, style: const TextStyle(color: ChaloColors.textPrimary, fontWeight: FontWeight.w600)),
                            ),
                            IconButton(
                              onPressed: _riderCap < 15 ? () => setState(() => _riderCap++) : null,
                              icon: const Icon(Icons.add_circle_outline, color: ChaloColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Label('MINIMUM RATING: ${_minRating.toStringAsFixed(1)}'),
                    Slider(
                      value: _minRating,
                      min: 3.0,
                      max: 4.5,
                      divisions: 3,
                      activeColor: ChaloColors.primary,
                      onChanged: (v) => setState(() => _minRating = v),
                    ),
                    const SizedBox(height: 12),
                    MetallicCard(
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text('Accept New Riders', style: TextStyle(color: ChaloColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                            ),
                            Switch(
                              value: _acceptNewRiders,
                              activeColor: ChaloColors.primary,
                              onChanged: (v) => setState(() => _acceptNewRiders = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Label('DESCRIPTION (OPTIONAL)'),
                    const SizedBox(height: 10),
                    _TextField(controller: _descriptionController, hint: 'Anything riders should know', maxLines: 3),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: ElevatedButton(onPressed: _post, child: const Text('Post Ride')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ChaloColors.textSecondary, letterSpacing: 1.2));
  }
}

class _DateTimeField extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSet;
  final VoidCallback onTap;

  const _DateTimeField({required this.icon, required this.label, required this.isSet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MetallicCard(
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 16, color: isSet ? ChaloColors.primary : ChaloColors.textDisabled),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSet ? ChaloColors.textPrimary : ChaloColors.textDisabled,
                    fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  const _TextField({required this.controller, required this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return MetallicCard(
      borderRadius: BorderRadius.circular(14),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: ChaloColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: ChaloColors.textDisabled, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
