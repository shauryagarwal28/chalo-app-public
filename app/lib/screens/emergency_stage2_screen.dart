import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

class EmergencyStage2Screen extends StatefulWidget {
  final String riderName;

  /// Seconds to start the visible countdown from. Defaults to 60 (the demo
  /// path's fixed value, unchanged); the real trigger path passes the
  /// server's own `emergency:confirm { countdown }` value instead of
  /// re-hardcoding it — see emergency-detection.md's "must be
  /// server-configurable, not hardcoded in the app" note.
  final int initialCountdownSeconds;

  /// True (default, matches the pre-existing demo behaviour): reaching 0
  /// with no tap auto-resolves as "needs help" locally. False for the real
  /// trigger path — the *server* is authoritative on the confirmation
  /// deadline (its own 60s timer independently fires `emergency:full_alert`
  /// on timeout, per emergency-detection.md step 5c), so this screen must
  /// not also independently decide "time's up, I'm popping myself" off a
  /// local clock that can drift from the server's. Instead it just stops
  /// ticking at 0 and stays up — the buttons remain tappable throughout,
  /// which happens to also be the right behaviour for "I Need Help ...
  /// any time, including after 60s" (emergency-detection.md's Resolution
  /// Paths). The screen is popped externally, by the caller, once a real
  /// `emergency:resolved`/`emergency:full_alert` server event actually
  /// arrives — see live_ride_screen.dart's `_onEmergencyFullAlert`/
  /// `_onEmergencyResolved`.
  final bool autoResolveOnTimeout;

  /// Called with `'fine'` or `'help'` when a button is tapped, *before*
  /// this screen pops itself. Null for the demo path (nothing to send).
  /// For the real path, the caller wires this to
  /// `LocationWsService.sendEmergencyRespond`.
  final void Function(String response)? onRespond;

  const EmergencyStage2Screen({
    super.key,
    required this.riderName,
    this.initialCountdownSeconds = 60,
    this.autoResolveOnTimeout = true,
    this.onRespond,
  });

  @override
  State<EmergencyStage2Screen> createState() => _EmergencyStage2ScreenState();
}

class _EmergencyStage2ScreenState extends State<EmergencyStage2Screen> {
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Not read in a field initializer above — `widget` isn't safely
    // available until after the State object is constructed, so this is
    // set here instead (a known Flutter State-class pitfall).
    _secondsLeft = widget.initialCountdownSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        if (widget.autoResolveOnTimeout) {
          _resolve(needsHelp: true);
        } else if (mounted) {
          setState(() => _secondsLeft = 0);
        }
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resolve({required bool needsHelp}) {
    _timer?.cancel();
    widget.onRespond?.call(needsHelp ? 'help' : 'fine');
    if (!mounted) return;
    Navigator.of(context).pop(needsHelp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_secondsLeft',
                style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: ChaloColors.primary),
              ),
              const SizedBox(height: 8),
              const Text(
                'seconds to respond',
                style: TextStyle(fontSize: 14, color: ChaloColors.textSecondary),
              ),
              const SizedBox(height: 40),
              const Text(
                'Are you okay?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: ChaloColors.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                'We noticed you stopped suddenly. If we don\'t hear from you, we\'ll alert the rest of ${widget.riderName == 'You' ? 'your' : "the"} party.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: ChaloColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _resolve(needsHelp: false),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                  child: const Text("I Am Fine", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _resolve(needsHelp: true),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    side: const BorderSide(color: Colors.redAccent, width: 1.5),
                    foregroundColor: Colors.redAccent,
                  ),
                  child: const Text("I Need Help", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
