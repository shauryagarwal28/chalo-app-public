import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_exception.dart';
import '../services/party_service.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'party_ready_screen.dart';

class CreatePartyScreen extends StatefulWidget {
  const CreatePartyScreen({super.key});

  @override
  State<CreatePartyScreen> createState() => _CreatePartyScreenState();
}

class _CreatePartyScreenState extends State<CreatePartyScreen> {
  final _nameController = TextEditingController();
  final _meetController = TextEditingController();
  DateTime? _rideDate;
  TimeOfDay? _rideTime;
  int _maxRiders = 2;
  bool _isCreating = false;

  bool get _canCreate =>
      _nameController.text.trim().isNotEmpty &&
      _meetController.text.trim().isNotEmpty &&
      _rideDate != null &&
      _rideTime != null &&
      !_isCreating;

  Future<void> _createParty() async {
    if (!_canCreate) return;
    setState(() => _isCreating = true);

    try {
      // Real backend call — POST /parties, per api-design.md. Replaces the
      // old client-generated fake room code with the real one the backend
      // hands back (Redis-backed, per backend-mvp-plan.md Task 4).
      final result = await PartyService.createParty(
        rideName: _nameController.text.trim(),
        meetPoint: _meetController.text.trim(),
        date: _rideDate!,
        hour24: _rideTime!.hour,
        minute: _rideTime!.minute,
        maxRiders: _maxRiders,
      );
      if (!mounted) return;
      setState(() => _isCreating = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PartyReadyScreen(
            partyId: result.partyId,
            roomCode: result.roomCode,
            rideName: _nameController.text.trim(),
            meetPoint: _meetController.text.trim(),
            date: _rideDate!,
            time: _rideTime!,
            maxRiders: _maxRiders,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create party: ${e.message}')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _meetController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _meetController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
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
    if (picked != null) setState(() => _rideDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 6, minute: 0),
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
    if (picked != null) setState(() => _rideTime = picked);
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

  static const _testRides = [
    ('Lonavala Sunday Run', 'Toll Plaza, Old Mumbai-Pune Highway'),
    ('Nandi Hills Sunrise Loop', 'Hebbal Flyover, Bengaluru'),
    ('Coastal Highway Cruise', 'Marine Drive, Mumbai'),
    ('Ridge Road Night Ride', 'ISBT, Chandigarh'),
    ('ECR Breakfast Run', 'Thiruvanmiyur Beach, Chennai'),
  ];

  /// Fills the form with plausible sample data so a tester doesn't have to
  /// type a ride name/meet point/date/time by hand every time they need a
  /// real party to test against (e.g. to hand a room code to a second
  /// device for testing Join Party) — added 2026-08-18 at the user's
  /// request, matching `otp_screen.dart`'s `debugOtp` auto-fill pattern:
  /// this only fills the fields, it does not submit. The real "Generate
  /// Party Code" button and its real `POST /parties` call are still
  /// exercised every time, not bypassed.
  void _fillTestData() {
    final rand = Random();
    final (name, meet) = _testRides[rand.nextInt(_testRides.length)];
    final suffix = rand.nextInt(900) + 100;
    final date = DateTime.now().add(Duration(days: rand.nextInt(6) + 1));
    final hour = rand.nextInt(12) + 6; // 6am–5pm, a plausible ride time
    setState(() {
      _nameController.text = '$name #$suffix';
      _meetController.text = meet;
      _rideDate = date;
      _rideTime = TimeOfDay(hour: hour, minute: rand.nextBool() ? 0 : 30);
      _maxRiders = rand.nextInt(4) + 2; // 2–5
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1.5, -1.5),
                    end: Alignment(1.5, 1.5),
                    colors: [Color(0xFF2A3540), Color(0xFF1A1F23), Color(0xFF1E2428), Color(0xFF1A1F23)],
                    stops: [0.0, 0.35, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: MetallicCard(
                          borderRadius: BorderRadius.circular(12),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.arrow_back_ios_new, color: ChaloColors.textSecondary, size: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Create Party',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),

                        // Fills the form with sample data for testing —
                        // doesn't submit, "Generate Party Code" below still
                        // does the real work. See _fillTestData()'s doc
                        // comment.
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _fillTestData,
                            icon: const Icon(Icons.auto_fix_high, size: 16),
                            label: const Text('Fill Test Data'),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Ride name
                        _Label('Ride Name'),
                        const SizedBox(height: 8),
                        MetallicCard(
                          borderRadius: BorderRadius.circular(14),
                          child: TextField(
                            controller: _nameController,
                            style: const TextStyle(color: ChaloColors.textPrimary, fontSize: 16),
                            decoration: const InputDecoration(
                              hintText: 'e.g. Lonavala Sunday Run',
                              hintStyle: TextStyle(color: ChaloColors.textDisabled, fontSize: 16),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Meet point
                        _Label('Meet Point'),
                        const SizedBox(height: 8),
                        MetallicCard(
                          borderRadius: BorderRadius.circular(14),
                          child: Row(
                            children: [
                              const SizedBox(width: 16),
                              const Icon(Icons.location_on_outlined, color: ChaloColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _meetController,
                                  style: const TextStyle(color: ChaloColors.textPrimary, fontSize: 16),
                                  decoration: const InputDecoration(
                                    hintText: 'Where are you starting from?',
                                    hintStyle: TextStyle(color: ChaloColors.textDisabled, fontSize: 15),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Date and time row
                        _Label('Date & Time'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _pickDate,
                                child: MetallicCard(
                                  borderRadius: BorderRadius.circular(14),
                                  hasOrangeAccent: _rideDate != null,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today_outlined,
                                          size: 18,
                                          color: _rideDate != null ? ChaloColors.primary : ChaloColors.textDisabled,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          _rideDate != null ? _formatDate(_rideDate!) : 'Date',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: _rideDate != null ? ChaloColors.textPrimary : ChaloColors.textDisabled,
                                            fontWeight: _rideDate != null ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: _pickTime,
                                child: MetallicCard(
                                  borderRadius: BorderRadius.circular(14),
                                  hasOrangeAccent: _rideTime != null,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.access_time_outlined,
                                          size: 18,
                                          color: _rideTime != null ? ChaloColors.primary : ChaloColors.textDisabled,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          _rideTime != null ? _formatTime(_rideTime!) : 'Time',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: _rideTime != null ? ChaloColors.textPrimary : ChaloColors.textDisabled,
                                            fontWeight: _rideTime != null ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Max riders
                        _Label('Max Riders'),
                        const SizedBox(height: 8),
                        MetallicCard(
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.people_outline, color: ChaloColors.textSecondary, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '$_maxRiders riders',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: ChaloColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                _RiderStepper(
                                  value: _maxRiders,
                                  onChanged: (v) => setState(() => _maxRiders = v),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Info note
                        MetallicCard(
                          borderRadius: BorderRadius.circular(12),
                          padding: const EdgeInsets.all(14),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.bolt, color: ChaloColors.primary, size: 18),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'A 6-character code will be generated. Share it with your riders to let them join.',
                                  style: TextStyle(fontSize: 12, color: ChaloColors.textSecondary, height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),

                // Create button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _canCreate
                          ? [BoxShadow(color: ChaloColors.primary.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 4))]
                          : [],
                    ),
                    child: ElevatedButton(
                      onPressed: _canCreate ? _createParty : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canCreate ? ChaloColors.primary : ChaloColors.bgCard,
                        disabledBackgroundColor: ChaloColors.bgCard,
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Generate Party Code',
                                  style: TextStyle(color: _canCreate ? Colors.white : ChaloColors.textDisabled),
                                ),
                                if (_canCreate) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool optional;
  const _Label(this.text, {this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.textSecondary, letterSpacing: 0.4),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          const Text('optional', style: TextStyle(fontSize: 11, color: ChaloColors.textDisabled)),
        ],
      ],
    );
  }
}

class _RiderStepper extends StatelessWidget {
  final int value;
  final void Function(int) onChanged;
  const _RiderStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepBtn(
          icon: Icons.remove,
          onTap: value > 2 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
          ),
        ),
        _StepBtn(
          icon: Icons.add,
          onTap: value < 15 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null ? ChaloColors.bgElevated : ChaloColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ChaloColors.borderDim),
        ),
        child: Icon(icon, size: 16, color: onTap != null ? ChaloColors.textPrimary : ChaloColors.textDisabled),
      ),
    );
  }
}
