import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_exception.dart';
import '../services/auth_service.dart';
import '../services/location_ws_service.dart';
import '../services/party_service.dart';
import '../theme/colors.dart';
import '../widgets/metallic_card.dart';
import 'live_ride_screen.dart';

class PartyReadyScreen extends StatefulWidget {
  final String partyId;
  final String roomCode;
  final String rideName;
  final String meetPoint;
  final DateTime date;
  final TimeOfDay time;
  final int maxRiders;

  const PartyReadyScreen({
    super.key,
    required this.partyId,
    required this.roomCode,
    required this.rideName,
    required this.meetPoint,
    required this.date,
    required this.time,
    required this.maxRiders,
  });

  @override
  State<PartyReadyScreen> createState() => _PartyReadyScreenState();
}

class _PartyReadyScreenState extends State<PartyReadyScreen> with SingleTickerProviderStateMixin {
  // Real, server-generated code (POST /parties, api-design.md) — was
  // hardcoded 'RD7K2X' before this screen's caller talked to a real backend.
  String get _partyCode => widget.roomCode;
  bool _copied = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  /// Opens the same party WS connection `live_ride_screen.dart` uses, for
  /// this screen's own real-time roster only — no location sending happens
  /// here (the ride hasn't started yet). A separate `LocationWsService`
  /// instance, deliberately not shared with the one S9 opens later: this
  /// screen's connection is disposed (per this State's own `dispose()`)
  /// the moment "Start Ride" navigates away, and `LiveRideScreen` always
  /// opens its own fresh connection on mount — same "one connection per
  /// screen's own lifecycle" shape the codebase already uses elsewhere,
  /// not a new pattern.
  ///
  /// Found 2026-08-15 (build-status.md's "Full end-to-end regression..."
  /// section): this screen never opened a WS connection at all, so (a) the
  /// "Riders joined" count never updated past the organiser-only "1", and
  /// (b) S9 fell back to "Rider XXXX" for a joined rider's name on the
  /// organiser's own device, since there was no live roster to seed
  /// `LiveRideScreen.initialMemberNames` from. Both are fixed by this one
  /// connection: `party:member_joined` (per Task 5, REST-`/parties/join`-
  /// triggered, so it fires even for a rider who joined and never opened
  /// their own WS) grows [_joinedMembers], which both feeds the "Riders
  /// joined" count/gate below and is threaded straight into
  /// `LiveRideScreen.initialMemberNames` on Start Ride.
  final _locationWs = LocationWsService();

  /// userId -> name, one entry per rider who has joined via `POST
  /// /parties/join` since this screen opened (i.e. everyone except the
  /// organiser themselves, who isn't included in their own roster count
  /// here — see `_ridersJoined` below).
  Map<String, String> _joinedMembers = {};

  /// Organiser (always present) + every rider in [_joinedMembers].
  int get _ridersJoined => 1 + _joinedMembers.length;

  /// Party Minimums (product/features/active-ride-mode.md, decided
  /// 2026-07-10): organiser + at least 1 rider before "Start Ride" unlocks.
  bool get _canStart => _ridersJoined >= 2;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _locationWs.riderNames.addListener(_onRosterChanged);
    _locationWs.lastError.addListener(_onWsError);
    final token = AuthSession.accessToken;
    if (token != null) {
      unawaited(_connectAndBackstopRoster(token));
    }
    // A missing token here would mean this screen is somehow reachable
    // without having completed the real phone/OTP flow — shouldn't happen
    // (same "shouldn't happen" class of guard live_ride_screen.dart's own
    // _initLocation uses) — silently leaves the roster at organiser-only
    // rather than crashing the screen over it.
  }

  /// **Fixed 2026-08-17** (process/build-status.md Next Steps item 29 —
  /// found live while first wiring this connection): opening the WS
  /// connection here is inherently racy against a rider joining via
  /// `POST /parties/join` fast enough to beat the server registering this
  /// socket in `partyRooms` (see `location_ws_service.dart`'s `connect()`
  /// doc comment for the now-fixed part of this and the small residual gap
  /// that remains even after that fix) — `broadcastPartyMemberJoined()`
  /// fires to a room this connection isn't in yet, and there's no
  /// catch-up/replay for a missed WS event by design (same "no replay"
  /// behavior Task 5's own design already has for `party:member_joined`
  /// generally).
  ///
  /// Reproduced live twice pre-fix: worked correctly with a few seconds'
  /// gap between this screen opening and the second rider joining (the
  /// common case — a human has to read/type a 6-character code), but failed
  /// silently (roster stuck at 1, Start Ride stayed disabled, no error
  /// shown) when the join happened within ~1-2 seconds of party creation.
  ///
  /// Fix: once [LocationWsService.connect] genuinely resolves (the client's
  /// own WS handshake has completed), fetch the real current membership via
  /// `GET /parties/:id` (`PartyService.getPartyDetail`) and merge it into
  /// [_joinedMembers] — a REST-sourced backstop that doesn't depend on the
  /// WS stream having delivered every event, only on the party's Redis
  /// state (the actual source of truth) being correct, which it always is.
  /// A rider who joins *after* this fetch is still covered by the live
  /// `party:member_joined` listener as before — this only closes the gap
  /// for a join that raced the connection itself.
  Future<void> _connectAndBackstopRoster(String token) async {
    await _locationWs.connect(token);
    if (!mounted) return;
    try {
      final detail = await PartyService.getPartyDetail(widget.partyId);
      if (!mounted) return;
      final selfId = AuthSession.userId;
      setState(() {
        _joinedMembers = {
          for (final member in detail.members)
            if (member.userId != selfId) member.userId: member.name,
        };
      });
    } on ApiException catch (e) {
      // Non-fatal — the roster simply stays whatever the live WS listener
      // has managed to deliver so far, same as before this fix existed.
      // Surfaced via the same lastError SnackBar path as a WS failure
      // (_onWsError below), since from this screen's perspective both are
      // "couldn't confirm who's really in this party right now."
      _locationWs.lastError.value = 'Could not refresh rider list — ${e.message}';
    }
  }

  void _onRosterChanged() {
    if (!mounted) return;
    setState(() {
      _joinedMembers = Map<String, String>.from(_locationWs.riderNames.value);
    });
  }

  /// New 2026-08-17, alongside the roster backstop above — this screen
  /// previously had no error surface at all for a stuck/failed connection
  /// (unlike `live_ride_screen.dart`, which already shows
  /// `_locationWs.lastError` as a SnackBar), which made the pre-fix race
  /// condition silent rather than merely non-blocking.
  void _onWsError() {
    final message = _locationWs.lastError.value;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _locationWs.riderNames.removeListener(_onRosterChanged);
    _locationWs.lastError.removeListener(_onWsError);
    _locationWs.dispose();
    super.dispose();
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _partyCode));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _shareLink() {
    Share.share(
      'Join my Chalo ride — ${widget.rideName}!\n\nParty code: $_partyCode\nMeet at: ${widget.meetPoint}\n\nOpen in Chalo: https://chalo.app/join/$_partyCode',
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
            child: Column(
              children: [
                // Top bar — every other stacked screen in the app has a
                // back chevron (see create_party_screen.dart); this one
                // had none, and swipe-back was reported exiting the app
                // instead of popping to Create Party. No documented
                // product reason found for this to be a deliberate
                // point-of-no-return, so matching the standard pattern.
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
                    ],
                  ),
                ),
                Expanded(
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
                              'Party Open — Waiting for Riders',
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

                  // Party code card
                  MetallicCard(
                    hasOrangeAccent: true,
                    borderRadius: BorderRadius.circular(20),
                    shadows: [
                      BoxShadow(color: ChaloColors.primary.withOpacity(0.3), blurRadius: 32, offset: const Offset(0, 8)),
                      BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
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
                            _partyCode,
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: ChaloColors.textPrimary,
                              letterSpacing: 12,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              // Copy code button
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
                              // Share link button
                              Expanded(
                                child: GestureDetector(
                                  onTap: _shareLink,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: ChaloColors.primary,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(color: ChaloColors.primary.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 2)),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.share_outlined, size: 15, color: Colors.white),
                                        SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Share Link',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
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
                          _DetailRow(
                            icon: Icons.location_on_outlined,
                            label: 'Meet at',
                            value: widget.meetPoint,
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'Date',
                            value: _formatDate(widget.date),
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            icon: Icons.access_time_outlined,
                            label: 'Time',
                            value: _formatTime(widget.time),
                          ),
                          if (widget.maxRiders > 0) ...[
                            const SizedBox(height: 12),
                            _DetailRow(
                              icon: Icons.people_outline,
                              label: 'Max riders',
                              value: '${widget.maxRiders}',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Riders joined (placeholder)
                  MetallicCard(
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
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
                            '$_ridersJoined / ${widget.maxRiders}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChaloColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // Start Ride button — gated per "Party Minimums"
                // (product/features/active-ride-mode.md, decided
                // 2026-07-10): organiser + at least 1 rider required.
                // Mirrors create_party_screen.dart's `_canCreate`-gated
                // "Generate Party Code" button (same disabled-styling
                // pattern, so this doesn't reintroduce the low-contrast
                // disabled-button bug already fixed elsewhere — see
                // process/build-status.md's Known Bugs).
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _canStart
                          ? [BoxShadow(color: ChaloColors.primary.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 4))]
                          : [],
                    ),
                    child: ElevatedButton(
                      onPressed: _canStart
                          ? () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LiveRideScreen(
                                    partyId: widget.partyId,
                                    rideName: widget.rideName,
                                    partyCode: _partyCode,
                                    maxRiders: widget.maxRiders,
                                    isOrganiser: true,
                                    initialMemberNames: _joinedMembers,
                                  ),
                                ),
                              )
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canStart ? ChaloColors.primary : ChaloColors.bgCard,
                        disabledBackgroundColor: ChaloColors.bgCard,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.two_wheeler, size: 20, color: _canStart ? Colors.white : ChaloColors.textDisabled),
                          const SizedBox(width: 10),
                          Text(
                            'Start Ride',
                            style: TextStyle(color: _canStart ? Colors.white : ChaloColors.textDisabled),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!_canStart) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      'Waiting for at least 1 rider to join',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: ChaloColors.textSecondary),
                    ),
                  ),
                  // Solo test bypass for the party-minimum gate above —
                  // there's no way to satisfy "organiser + at least 1
                  // rider" on one device without a second real join, so
                  // this lets a single tester reach S9 anyway. Demo-only,
                  // same pattern as waiting_room_screen.dart's "Simulate:
                  // Host Started Ride" button; only shown while the real
                  // gate is unmet, so it disappears once a real second
                  // rider actually joins.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveRideScreen(
                            partyId: widget.partyId,
                            rideName: widget.rideName,
                            partyCode: _partyCode,
                            maxRiders: widget.maxRiders,
                            isOrganiser: true,
                            initialMemberNames: _joinedMembers,
                          ),
                        ),
                      ),
                      child: const Text('Simulate: Start Solo (test only)'),
                    ),
                  ),
                ] else
                  const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
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
