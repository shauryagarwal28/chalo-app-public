import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'live_ride_screen.dart';

class WaitingRoomScreen extends StatefulWidget {
  final String partyId;
  final String rideName;
  final String meetPoint;
  final DateTime date;
  final TimeOfDay time;
  final int maxRiders;
  final String partyCode;
  final String hostName;

  /// userId -> name for every member already in the party at join time
  /// (POST /parties/join's `members` response), so live_ride_screen.dart
  /// can label markers/party-menu rows for riders it hasn't received a
  /// `party:member_joined` event for (i.e. everyone who joined before this
  /// device's own WS connection opened) — see party_service.dart's
  /// file-level note on the related empty-name gap.
  final Map<String, String> initialMemberNames;

  const WaitingRoomScreen({
    super.key,
    required this.partyId,
    required this.rideName,
    required this.meetPoint,
    required this.date,
    required this.time,
    required this.maxRiders,
    required this.partyCode,
    required this.hostName,
    this.initialMemberNames = const {},
  });

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> with SingleTickerProviderStateMixin {
  bool _copied = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.partyCode));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _shareLink() {
    Share.share(
      'Join my Chalo ride — ${widget.rideName}!\n\nParty code: ${widget.partyCode}\nMeet at: ${widget.meetPoint}\n\nOpen in Chalo: https://chalo.app/join/${widget.partyCode}',
      subject: 'Join my ride on Chalo',
    );
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // Status indicator
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: ChaloColors.primary.withOpacity(0.12 * _pulseAnim.value),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: ChaloColors.primary.withOpacity(0.5 * _pulseAnim.value),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ChaloColors.primary.withOpacity(_pulseAnim.value),
                              boxShadow: [BoxShadow(color: ChaloColors.primary.withOpacity(0.4), blurRadius: 6)],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Waiting for ${widget.hostName} to Start',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ChaloColors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Ride name
                  Text(
                    widget.rideName,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ChaloColors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Party code card (read-only for a member, but still shareable)
                  MetallicCard(
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
                      child: Column(
                        children: [
                          const Text(
                            'PARTY CODE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ChaloColors.textSecondary,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.partyCode,
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: ChaloColors.textPrimary,
                              letterSpacing: 10,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: _copyCode,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _copied ? ChaloColors.primary.withOpacity(0.2) : ChaloColors.bgElevated,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _copied ? ChaloColors.primary : ChaloColors.borderShine,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _copied ? Icons.check : Icons.copy_outlined,
                                          size: 15,
                                          color: _copied ? ChaloColors.primary : ChaloColors.textSecondary,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            _copied ? 'Copied!' : 'Copy Code',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: _copied ? ChaloColors.primary : ChaloColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _shareLink,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: ChaloColors.bgElevated,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: ChaloColors.borderShine),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.share_outlined, size: 15, color: ChaloColors.textSecondary),
                                        SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Share Link',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.textSecondary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Ride details
                  MetallicCard(
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _DetailRow(icon: Icons.location_on_outlined, label: 'Meet at', value: widget.meetPoint),
                          const SizedBox(height: 12),
                          _DetailRow(icon: Icons.calendar_today_outlined, label: 'Date', value: _formatDate(widget.date)),
                          const SizedBox(height: 12),
                          _DetailRow(icon: Icons.access_time_outlined, label: 'Time', value: _formatTime(widget.time)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Member list
                  MetallicCard(
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.people_outline, color: ChaloColors.textSecondary, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Riders joined',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, color: ChaloColors.textSecondary),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '2 / ${widget.maxRiders}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _MemberRow(name: widget.hostName, isHost: true),
                          const SizedBox(height: 10),
                          const _MemberRow(name: 'You', isHost: false),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Wait-state — no Start Ride control for a member
                  MetallicCard(
                    borderRadius: BorderRadius.circular(16),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.hourglass_empty, size: 18, color: ChaloColors.textSecondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Only ${widget.hostName} can start this ride. Sit tight.',
                            style: const TextStyle(fontSize: 13, color: ChaloColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // No backend yet to signal "host started the ride" in real
                  // time — demo-only trigger, same pattern as KYC's
                  // "Simulate: Approved" button.
                  OutlinedButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveRideScreen(
                          partyId: widget.partyId,
                          rideName: widget.rideName,
                          partyCode: widget.partyCode,
                          maxRiders: widget.maxRiders,
                          isOrganiser: false,
                          initialMemberNames: widget.initialMemberNames,
                        ),
                      ),
                    ),
                    child: const Text('Simulate: Host Started Ride (demo only)'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final String name;
  final bool isHost;

  const _MemberRow({required this.name, required this.isHost});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ChaloColors.bgElevated,
            border: Border.all(color: ChaloColors.borderShine.withOpacity(0.5)),
          ),
          alignment: Alignment.center,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ChaloColors.textPrimary),
          ),
        ),
        if (isHost)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ChaloColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ChaloColors.primary.withOpacity(0.4)),
            ),
            child: const Text(
              'HOST',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: ChaloColors.primary, letterSpacing: 0.5),
            ),
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ChaloColors.primary),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13, color: ChaloColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChaloColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
